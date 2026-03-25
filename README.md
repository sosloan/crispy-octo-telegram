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
    store.rb              # In-memory data store + seed data
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

#### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET`  | `/`  | Health check |
| `GET`  | `/schema` | Schema introspection (JSON) |
| `POST` | `/genql` | Execute a GenQL query or mutation |

#### Example queries

```sh
# List all orchards with their varieties
curl -s -XPOST http://localhost:9292/genql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ orchards { name location varieties { name season } } }"}'

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

### Running the tests

```sh
bundle exec rspec
```

---

### GenQL query syntax

```
# Read query (bare braces default to "query")
{
  orchards {
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
