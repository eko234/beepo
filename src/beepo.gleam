import mist
import gleam/erlang/os
import gleam/io
import gleam/dynamic.{Dynamic}
import gleam/result
import gleam/int
import gleam/string
import gleam/bit_string
import gleam/bit_builder
import gleam/erlang/process as ep
import mist/handler.{Response, Upgrade}
import glisten/handler.{HandlerMessage} as gh
import mist/http.{BitBuilderBody} as mhttp
import gleam/http.{Get, Post}
import gleam/option.{Some}
import gleam/http/request
import gleam/http/response
import mist/websocket
import gleam/erlang/atom.{Atom}

pub external fn e_del(r, k) -> Bool =
  "ets" "delete"

pub external fn e_ins(r, o) -> Bool =
  "ets" "insert"

pub external fn e_lu(r, k) -> List(Dynamic) =
  "ets" "lookup"

pub external fn e_new(n, o) -> Atom =
  "ets" "new"

pub external fn e_match(r, p) -> List(Dynamic) =
  "ets" "match"

pub type ClientsCollection {
  ClientsCollection(
    match: fn(Dynamic) -> List(Dynamic),
    lu: fn(String) -> List(Dynamic),
    ins: fn(#(String, List(ep.Subject(HandlerMessage)))) -> Bool,
    del: fn(String) -> Bool,
  )
}

pub type Logger {
  Logger(log: fn(String) -> Nil)
}

pub type Deps {
  Deps(clients: ClientsCollection, logger: Logger)
}

pub fn main() {
  let port =
    os.get_env("PORT")
    |> result.then(int.parse)
    |> result.unwrap(3002)

  assert Ok(data) = atom.from_string("data")
  assert Ok(public) = atom.from_string("public")
  assert Ok(_bag) = atom.from_string("bag")
  assert Ok(_one) = atom.from_string("$1")
  assert Ok(_any) = atom.from_string("_")
  assert clients_table = e_new(data, [public])

  let clients =
    ClientsCollection(
      match: fn(d) { e_match(clients_table, d) },
      ins: fn(d) { e_ins(clients_table, d) },
      del: fn(d) { e_del(clients_table, d) },
      lu: fn(d) { e_lu(clients_table, d) },
    )

  let deps =
    Deps(
      clients,
      logger: Logger(log: fn(m: String) {
        [m]
        |> string.concat
        |> io.println
        Nil
      }),
    )

  assert Ok(_) =
    mist.serve(
      port,
      handler.with_func(fn(req) {
        case req.method, request.path_segments(req) {
          Get, [token] ->
            websocket.WebsocketHandler(
              on_close: Some(fn(s: ep.Subject(HandlerMessage)) {
                let _ = deps.clients.del(token)
                deps.logger.log(
                  ["Bye fren: ", string.inspect(s), ":", token]
                  |> string.concat,
                )
              }),
              on_init: Some(fn(s: ep.Subject(HandlerMessage)) {
                deps.clients.ins(#(token, [s]))
                deps.logger.log(
                  ["Hi buddy: ", string.inspect(s), ":", token]
                  |> string.concat,
                )
              }),
              handler: fn(_m: websocket.Message, _s: ep.Subject(HandlerMessage)) {
                Ok(Nil)
              },
            )
            |> Upgrade
          Post, [token] ->
            req
            |> mhttp.read_body
            |> result.map(fn(req) {
              let [d] = deps.clients.lu(token)
              let #(_, [s]) = dynamic.unsafe_coerce(d)
              assert Ok(message) = bit_string.to_string(req.body)
              websocket.send(s, websocket.TextMessage(message))
              io.debug(s)
              response.new(200)
              |> response.set_body(BitBuilderBody(bit_builder.from_bit_string(<<
                "SENT":utf8,
              >>)))
            })
            |> result.unwrap(
              response.new(400)
              |> response.set_body(BitBuilderBody(bit_builder.new())),
            )
            |> Response
        }
      }),
    )

  ["Started listening on localhost:", int.to_string(port), " ✨"]
  |> string.concat
  |> io.println
  ep.sleep_forever()
}
