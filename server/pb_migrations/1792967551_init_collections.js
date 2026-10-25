/// <reference path="../pb_data/types.d.ts" />

// Datenbank-Struktur für den Dartzähler.
//
// games   – Online-Matches: Gastgeber legt an (Status "waiting"), Gast tritt per Code bei,
//           danach schreiben beide abwechselnd den kompletten Spielstand (state) mit
//           steigender Versionsnummer.
// matches – Historie in der Cloud: beendete Matches (kompletter Verlauf als JSON).

migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  const signedIn = '@request.auth.id != ""'
  const isPlayer = "(host = @request.auth.id || guest = @request.auth.id)"

  const games = new Collection({
    type: "base",
    name: "games",
    listRule: `${signedIn} && (${isPlayer} || status = "waiting")`,
    viewRule: `${signedIn} && (${isPlayer} || status = "waiting")`,
    createRule: `${signedIn} && @request.body.host = @request.auth.id && @request.body.status = "waiting"`,
    // Mitspieler dürfen ändern; ein Fremder darf nur sich selbst als Gast eintragen.
    // Der Gastgeber lässt sich nie ändern.
    updateRule: `${signedIn} && (@request.body.host:isset = false || @request.body.host = host) && ` +
      `(${isPlayer} || (guest = "" && status = "waiting" && @request.body.guest = @request.auth.id))`,
    deleteRule: "host = @request.auth.id",
    fields: [
      { name: "code", type: "text", required: true, min: 5, max: 8 },
      { name: "host", type: "relation", required: true, collectionId: users.id, maxSelect: 1 },
      { name: "guest", type: "relation", collectionId: users.id, maxSelect: 1 },
      // Anzeigenamen – Mitspieler dürfen das Benutzerprofil des anderen nicht lesen
      { name: "hostName", type: "text", max: 40 },
      { name: "guestName", type: "text", max: 40 },
      { name: "status", type: "select", required: true, maxSelect: 1, values: ["waiting", "playing", "finished", "aborted"] },
      { name: "settings", type: "json", maxSize: 100000 },
      { name: "state", type: "json", maxSize: 2000000 },
      { name: "version", type: "number", onlyInt: true },
      { name: "created", type: "autodate", onCreate: true },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_games_code ON games (code)"],
  })
  app.save(games)

  const matches = new Collection({
    type: "base",
    name: "matches",
    listRule: `${signedIn} && (owner = @request.auth.id || participants.id ?= @request.auth.id)`,
    viewRule: `${signedIn} && (owner = @request.auth.id || participants.id ?= @request.auth.id)`,
    createRule: `${signedIn} && @request.body.owner = @request.auth.id`,
    updateRule: "owner = @request.auth.id",
    deleteRule: "owner = @request.auth.id",
    fields: [
      { name: "owner", type: "relation", required: true, collectionId: users.id, maxSelect: 1 },
      { name: "participants", type: "relation", collectionId: users.id, maxSelect: 8 },
      { name: "matchId", type: "text", required: true, max: 64 },
      { name: "mode", type: "text", max: 40 },
      { name: "description", type: "text", max: 200 },
      { name: "finished", type: "date" },
      { name: "data", type: "json", maxSize: 5000000 },
      { name: "created", type: "autodate", onCreate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_matches_owner_match ON matches (owner, matchId)"],
  })
  app.save(matches)
}, (app) => {
  app.delete(app.findCollectionByNameOrId("matches"))
  app.delete(app.findCollectionByNameOrId("games"))
})
