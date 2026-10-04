# A Room process holds the live Game state, not the database

Each open Room is one GenServer that holds its Room and Game state in memory and drives a pure rules core. Every 5 s, if something changed, it saves the Room and the Game (never the current Round's dice) to SQLite, and it saves once more on shutdown. We deliberately depart from Botify's Painless Phoenix rule that "the database is the state": a real-time game needs every Bid handled quickly and one at a time, and a Round lost to a crash or deploy costs only a re-roll, because a restore voids the current Round just as a Player leaving does.

## Considered Options

- **Database as the state** (Botify's rule): every action is a database transaction. It survives deploys, but it puts a database round trip on every Bid and stores secret dice.
- **Save the Round too, dice included:** a restore could bring back a Round older than what Players saw, and the dice would sit in the database.

## Consequences

- The app runs on one server with no clustering, because the `Registry` that finds Rooms only works on one server.
- The Room delivers updates by monitoring each registered LiveView and sending it `view_for(room, person)`. Being Away means having no live LiveViews. Each LiveView monitors the Room and joins again if the Room restarts.
- Timers (Host handover, vote window, Room closing) are stored as timestamps, so a restored Room can set them again.
- Deploys stop the old container before starting the new one, not zero-downtime. Two live copies would each run the same Room, and the old copy's final save would overwrite the new one's state.
