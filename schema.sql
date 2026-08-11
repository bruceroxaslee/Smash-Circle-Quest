-- Smash Circle Quest (SCQ) Supabase schema
-- Public clients can SELECT only the public projection.
-- Queue Master mutations are performed through PIN-checked SECURITY DEFINER RPCs.
-- Never place a service-role key in browser code.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- SCQ PINs use a deterministic SHA-256 digest so the browser login works
-- consistently on Supabase without relying on bcrypt settings.
create or replace function public.scq_pin_hash(p_pin text)
returns text
language sql
immutable
strict
set search_path = public, extensions
as $$ select encode(digest(coalesce(p_pin,''), 'sha256'), 'hex') $$;

create table if not exists public.scq_private_state (
  id integer primary key check (id = 1),
  state jsonb not null,
  pin_hash text not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.scq_public_state (
  id integer primary key check (id = 1),
  state jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.scq_private_state enable row level security;
alter table public.scq_public_state enable row level security;

drop policy if exists "public can read SCQ public state" on public.scq_public_state;
create policy "public can read SCQ public state"
on public.scq_public_state for select
to anon, authenticated
using (true);

-- No direct public INSERT/UPDATE/DELETE policies are created.

create or replace function public.scq_make_public(p_state jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  players jsonb := '[]'::jsonb;
  used_ids text[] := array[]::text[];
  item jsonb;
  pid text;
  q jsonb;
  c jsonb;
  m jsonb;
begin
  -- Only players appearing in the current queue, courts or recent matches
  -- are included in the public projection. Payment data is never copied.
  for q in select value from jsonb_array_elements(coalesce(p_state #> '{session,queue}', '[]'::jsonb))
  loop
    pid := q->>'playerId';
    if pid is not null and not (pid = any(used_ids)) then
      used_ids := array_append(used_ids,pid);
    end if;
  end loop;

  for c in select value from jsonb_array_elements(coalesce(p_state #> '{session,courts}', '[]'::jsonb))
  loop
    for item in select value from jsonb_array_elements(coalesce(c->'players','[]'::jsonb))
    loop
      pid := item #>> '{}';
      if pid is not null and not (pid = any(used_ids)) then
        used_ids := array_append(used_ids,pid);
      end if;
    end loop;
  end loop;

  for m in select value from jsonb_array_elements(coalesce(p_state #> '{session,matches}', '[]'::jsonb))
  loop
    for item in select value from jsonb_array_elements(coalesce(m->'players','[]'::jsonb))
    loop
      pid := item #>> '{}';
      if pid is not null and not (pid = any(used_ids)) then
        used_ids := array_append(used_ids,pid);
      end if;
    end loop;
  end loop;

  for item in select value from jsonb_array_elements(coalesce(p_state #> '{persistent,players}', '[]'::jsonb))
  loop
    pid := item->>'id';
    if pid = any(used_ids) then
      players := players || jsonb_build_array(jsonb_build_object(
        'id',item->>'id','name',item->>'name','level',item->>'level'
      ));
    end if;
  end loop;

  return jsonb_build_object(
    'persistent', jsonb_build_object(
      'clubName','Smash Circle Quest',
      'openPlayFee', coalesce((p_state #>> '{persistent,openPlayFee}')::numeric,0),
      'logoDataUrl', coalesce(p_state #>> '{persistent,logoDataUrl}','scq_logo.png'),
      'players', players
    ),
    'session', jsonb_build_object(
      'startedAt', p_state #>> '{session,startedAt}',
      'queue', coalesce(p_state #> '{session,queue}','[]'::jsonb),
      'courts', coalesce(p_state #> '{session,courts}','[]'::jsonb),
      'matches', coalesce(p_state #> '{session,matches}','[]'::jsonb)
    ),
    'meta', jsonb_build_object('updatedAt', now())
  );
end $$;

create or replace function public.qm_verify_pin(p_pin text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  return exists(
    select 1 from public.scq_private_state
    where id=1 and public.scq_pin_hash(coalesce(p_pin,''))=pin_hash
  );
end $$;

create or replace function public.qm_read_state(p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare out_state jsonb;
begin
  select state into out_state from public.scq_private_state
  where id=1 and public.scq_pin_hash(coalesce(p_pin,''))=pin_hash;
  if out_state is null then
    raise exception 'Invalid Queue Master PIN';
  end if;
  return out_state;
end $$;

create or replace function public.qm_write_state(p_pin text,p_state jsonb)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.scq_private_state
  set state=p_state, updated_at=now()
  where id=1 and public.scq_pin_hash(coalesce(p_pin,''))=pin_hash;

  if not found then raise exception 'Invalid Queue Master PIN'; end if;

  insert into public.scq_public_state(id,state,updated_at)
  values(1,public.scq_make_public(p_state),now())
  on conflict(id) do update set state=excluded.state,updated_at=now();

  return true;
end $$;

create or replace function public.qm_change_pin(p_old_pin text,p_new_pin text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if length(coalesce(p_new_pin,'')) < 4 then raise exception 'PIN must be at least 4 characters'; end if;
  update public.scq_private_state
  set pin_hash=public.scq_pin_hash(p_new_pin), updated_at=now()
  where id=1 and public.scq_pin_hash(coalesce(p_old_pin,''))=pin_hash;
  if not found then raise exception 'Invalid current PIN'; end if;
  return true;
end $$;

revoke all on public.scq_private_state from anon, authenticated;
revoke all on public.scq_public_state from anon, authenticated;
grant select on public.scq_public_state to anon, authenticated;
grant execute on function public.qm_verify_pin(text) to anon, authenticated;
grant execute on function public.qm_read_state(text) to anon, authenticated;
grant execute on function public.qm_write_state(text,jsonb) to anon, authenticated;
grant execute on function public.qm_change_pin(text,text) to anon, authenticated;

-- First-run state. The default Queue Master PIN is 1234; change it immediately.
insert into public.scq_private_state(id,state,pin_hash)
values (
  1,
  '{
    "persistent":{"clubName":"Smash Circle Quest","openPlayFee":100,"logoDataUrl":"scq_logo.png","courtCount":4,"players":[]},
    "session":{"startedAt":0,"queue":[],"courts":[
      {"id":1,"players":[],"startedAt":null,"groupId":null},
      {"id":2,"players":[],"startedAt":null,"groupId":null},
      {"id":3,"players":[],"startedAt":null,"groupId":null},
      {"id":4,"players":[],"startedAt":null,"groupId":null}
    ],"matches":[],"payments":{},"setRequests":[] },
    "meta":{"updatedAt":0}
  }'::jsonb,
  public.scq_pin_hash('1234')
)
on conflict(id) do update
set pin_hash = public.scq_pin_hash('1234'),
    updated_at = now();

-- If this script is rerun on an existing SCQ installation, the Queue Master PIN
-- is deliberately restored to the documented initial PIN 1234 without clearing
-- the saved player directory, logo, club settings, or current session state.

insert into public.scq_public_state(id,state)
select 1, public.scq_make_public(state)
from public.scq_private_state where id=1
on conflict(id) do update
set state=excluded.state, updated_at=now();
