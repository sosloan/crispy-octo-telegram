# crispy-octo-telegram

## Saratoga Orchards — GenQL Backend

A GraphQL-inspired backend for Saratoga Orchards, written in Ruby.

> *"The system has multiple kinds of intent, and each kind gets compiled into the language best suited to express or enforce it."*

---

### What is GenQL?

**GenQL** is an *executable theory of coordination* — a lightweight query language and execution engine inspired by GraphQL.  It answers three architectural questions:

| Question | Answer |
|---|---|
| How do languages coexist? | Schema types are Ruby objects; queries are a DSL string; HTTP transport is JSON |
| How are roles separated? | **Schema** = structure · **Resolver** = behaviour · **Type** = contract |
| How does the system absorb complexity? | The executor traverses, resolves, and coerces — callers only describe *what* they want |

Each kind of intent is compiled into the language best suited for it:
- **Data shape** → `GenQL::ObjectType` schema definition (Ruby DSL)
- **Read intent** → GenQL query document (`{ orchards { name varieties { name } } }`)
- **Write intent** → GenQL mutation document (`mutation { addHarvest(...) { id } }`)
- **Wire format** → JSON

---

### Directory structure

```
lib/
  gen_ql.rb               # Entry point; requires all GenQL modules
  gen_ql/
    ast.rb                # AST node structs (Document, Operation, Field)
    lexer.rb              # Tokeniser
    parser.rb             # Recursive-descent parser
    type.rb               # Type system (ObjectType, FieldDefinition, scalars, Schema)
    executor.rb           # Query executor
  saratoga/
    database.rb           # SQLite connection, schema migrations, and seed data
    store.rb              # SQLite-backed repository (Variety, Orchard, Harvest)
    schema.rb             # Saratoga-specific GenQL schema (types + resolvers)
app.rb                    # Sinatra HTTP application
config.ru                 # Rack entry point
spec/                     # RSpec test suite
```

---

### Running the server

```sh
bundle install
bundle exec rackup
```

The server starts on `http://localhost:9292`.

By default the server stores data in `saratoga.db` in the working directory.
Set the `SARATOGA_DATABASE_PATH` environment variable to use a different path:

```sh
SARATOGA_DATABASE_PATH=/var/data/saratoga.db bundle exec rackup
```

#### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET`  | `/`  | Health check |
| `GET`  | `/schema` | Schema introspection (JSON) |
| `POST` | `/genql` | Execute a GenQL query or mutation |

#### Example queries

```sh
# List the first page of orchards with their varieties (infinite scroll)
curl -s -XPOST http://localhost:9292/genql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ orchards(first: 2) { nodes { name location varieties { name season } } page_info { has_next_page end_cursor } } }"}'

# Fetch the next page using the cursor returned above
curl -s -XPOST http://localhost:9292/genql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ orchards(first: 2, after: \"o2\") { nodes { name } page_info { has_next_page end_cursor } } }"}'

# Fetch a single orchard by id
curl -s -XPOST http://localhost:9292/genql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ orchard(id: \"o1\") { name harvests { quantity_kg harvested_at } } }"}'

# Record a new harvest
curl -s -XPOST http://localhost:9292/genql \
  -H 'Content-Type: application/json' \
  -d '{"query":"mutation { addHarvest(orchard_id: \"o1\", variety_id: \"v1\", quantity_kg: 800, harvested_at: \"2024-09-01\") { id quantity_kg } }"}'
```

---

### Offline support (data persistence)

The server operates entirely without an external database.  All static
reference data (orchards, apple varieties) is embedded as seed data.  Harvests
recorded via the `addHarvest` mutation are saved to a local JSON file so they
survive server restarts.

By default the file is written to `data/store.json` in the project root.
Override the path with the `SARATOGA_DATA_FILE` environment variable:

```sh
SARATOGA_DATA_FILE=/var/data/saratoga.json bundle exec rackup
```

When no file exists the server falls back to the built-in seed harvests,
so the service starts cleanly even on a brand-new deployment.

---

### Running the tests

```sh
bundle exec rspec
```

---

### GenQL query syntax

List fields (`orchards`, `varieties`, `harvests`) now return **connection types** that
support cursor-based pagination for infinite scroll.  Every connection exposes:

| Field | Type | Description |
|-------|------|-------------|
| `nodes` | `[T]` | The items on this page |
| `page_info.has_next_page` | `Boolean` | `true` when more items follow |
| `page_info.end_cursor` | `String` | Pass as `after` to fetch the next page |
| `page_info.start_cursor` | `String` | Cursor of the first item on this page |

Arguments accepted by every list field:

| Argument | Type | Description |
|----------|------|-------------|
| `first` | `Int` | Maximum number of items to return |
| `after` | `ID` | Return items after this cursor (the previous page's `end_cursor`) |

```
# Read query — all orchards, no pagination (bare braces default to "query")
{
  orchards {
    nodes {
      name
      location
      established_year
      varieties {
        name
        season
      }
      harvests {
        id
        quantity_kg
        harvested_at
        variety { name }
      }
    }
    page_info { has_next_page end_cursor }
  }
}

# Paginated list — first page of 2 orchards
{
  orchards(first: 2) {
    nodes { id name location }
    page_info { has_next_page end_cursor }
  }
}

# Next page — use end_cursor from the previous response
{
  orchards(first: 2, after: "o2") {
    nodes { id name location }
    page_info { has_next_page end_cursor }
  }
}

# Explicit operation type with arguments
query {
  orchard(id: "o1") {
    name
    varieties { name species notes }
  }
}

# Mutation
mutation {
  addHarvest(
    orchard_id: "o1",
    variety_id: "v2",
    quantity_kg: 500,
    harvested_at: "2024-10-01"
  ) {
    id
    orchard_id
    variety_id
    quantity_kg
    harvested_at
  }
}
```
