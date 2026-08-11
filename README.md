SMASH CIRCLE QUEST — FIRST RUN / QA NOTES

1. Windows users: double-click START_SCQ.bat.
   Never open app.js directly with Windows Script Host.

2. Queue Master PIN
   Default PIN: 1234
   If you use Supabase, run schema.sql once in Supabase SQL Editor before testing the
   Queue Master cloud login. The schema initializes/restores the documented PIN without
   deleting the persistent player directory, logo, club settings, Open Play Fee or court count.

3. Tabs
   Queue → Players → Player's Directory → Ranking → Payments → Settings
   Queue contains the courts at the top, then Up Next, Active Players, Set Requests and
   Recent Game Results. There is no separate Courts tab.

4. Queue behavior
   Players remain members of the current session queue after playing. Completing a game
   returns them to the waiting queue with a new waiting timestamp. A player leaves the
   current queue only when QM removes/replaces them or a New Session is confirmed.

5. Courts
   Courts are configurable under Settings. The court cards use a vertical rectangular
   badminton-court layout with Team A at the top and Team B at the bottom.
   Completed and Choose / Replace share a compact action row. To swap teammates, drag one
   player directly onto the other player's name on the court; no separate swap button is needed.

6. Stats visibility
   Games/Wins/Losses/Win Rate are shown in Players, Up Next and Ranking only.
   Player's Directory is intentionally profile-focused and does not show match statistics.

7. Public Player View
   Open from Queue Master with Public Player View or use Copy URL. Public view contains
   only the allowed live player information. Newly called players trigger a five-second
   NOW PLAYING announcement; browsers may require prior interaction before allowing sound.

8. Supabase security
   Never put a service-role/secret key in browser code. Use the public anon key only.
   Queue Master writes are protected by the server-side PIN RPCs in schema.sql.

9. Persistent data
   New Session clears current queue, courts, matches/ranking and payment records, but
   preserves the saved Player's Directory, logo, club name/settings, Open Play Fee and
   configured court count.

FINAL QA PERFORMED FOR THIS PACKAGE
- JavaScript syntax checked with: node --check app.js
- All required files present
- ZIP integrity checked
- Supplied SCQ logo hash verified against packaged logo
- Ranking / Payments / Settings tab render functions verified
- Every data-action in app.js has a corresponding handler
- Directory match statistics removed
- Vertical portrait court layout verified in CSS and court markup
- Court action grid verified: compact Completed and Choose/Replace controls; direct drag-to-player swapping

MATCHMAKING REFERENCE NOTE
--------------------------
SCQ's matchmaking priority was refined using the public ShuttleFlow badminton queueing
approach as a reference. ShuttleFlow publicly describes smart suggestions around skill,
recency/wait time and balanced matches; community discussion also describes games played,
skill level, randomization and reduced repeated pairings. SCQ intentionally makes games
played the hard PRIMARY priority per the club's requirements, with level as the SECONDARY
filter, then partner rotation/randomization among otherwise equivalent choices.

FINAL UPDATE — RESULT / SET REQUEST / PUBLIC VIEW FIXES
- Set Request player selection now uses a visible, scrollable player picker with search, full names, level, and Games/Wins/Losses, sorted least-games-first by default. Team A is selected first, then Team B.
- Payment state is preserved when opening and leaving Public Player View. Returning to the Queue Master dashboard restores the private cloud state rather than the public projection.
- Recent Game Results now include Edit Winner. Correcting a result immediately recalculates wins, losses, win rate, and Ranking because those values are derived from the saved match records.
- Active Players shows full names and only the Add to Queue action; standings/statistics are intentionally omitted there.
