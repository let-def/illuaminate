(** A node is an object which exists in the syntax tree of the program.

    Nodes, along with holding an object, also include additional metadata such as their position and
    surrounding trivia. *)

(** A "trivial" part of the program, which is not important for the execution of the program, but
    may be useful for understanding or recreating it. *)
type trivial =
  | LineComment of string  (** A short, comment which is terminated by a newline. *)
  | BlockComment of int * string  (** A long comment, which may span multiple lines. *)
  | Whitespace of string  (** Any whitespace, such as spaces, newlines or tabs. *)
[@@deriving show]

(** A node, such as a token or identifier, but with additional metadata.

    Every node has leading and trailing trivia, represented as a list of {!Span.spanned} {!trivial}
    nodes. Nodes generated by the parser will generally have a {!Node} type, while generated nodes
    (who have not got any trivia) are built from {!SimpleNode} s. *)
type 'a t =
  | SimpleNode of { contents : 'a }
      (** A "simple" node, which was generated by the compiler rather than taken from source code. *)
  | Node of
      { leading_trivia : trivial Span.spanned list;
        trailing_trivia : trivial Span.spanned list;
        contents : 'a;
        span : Span.t  (** The position of the node, not including leading or trailing trivia. *)
      }
      (** A token with full metadata, which can {i generally} be traced to a concrete position in
          the source code. *)
[@@deriving show]

(** Update the contents of this node. *)
let with_contents contents = function
  | SimpleNode _ -> SimpleNode { contents }
  | Node n -> Node { n with contents }

(** Get the span of this node, if defined. Otherwise throw an exception. *)
let span = function
  | Node { span; _ } -> span
  | SimpleNode _ -> failwith "No span."

(** Get the span of the first trivia node, or the current node *)
let trivia_start = function
  | Node { span; leading_trivia; _ } -> (
    match leading_trivia with
    | [] -> span
    | t :: _ -> t.span)
  | SimpleNode _ -> failwith "No span."

(** Get the span of the last trivia node, or the current node *)
let trivia_finish = function
  | Node { span; trailing_trivia; _ } -> (
    match CCList.last_opt trailing_trivia with
    | None -> span
    | Some t -> t.span)
  | SimpleNode _ -> failwith "No span."

(** Get the span of this node, including trivia of this node. *)
let trivia_span n = Span.of_span2 (trivia_start n) (trivia_finish n)

open Illuaminate.Lens

(** A lens which exposes the contents of the term. *)
let contents =
  let get (SimpleNode { contents } | Node { contents; _ }) = contents
  and over f = function
    | SimpleNode n -> SimpleNode { contents = f n.contents }
    | Node n -> Node { n with contents = f n.contents }
  in
  { get; over }

(** Embed a lens which transforms the whole node with a view on the body. *)
let lens_embed (type s u a b) (inner : (s, u, a, b) lens) : (s t, u t, a t, b t) lens =
  { get = contents %= inner.get;
    over =
      (fun f x ->
        let body = x ^. contents in
        let res = contents.over inner.get x |> f in
        with_contents (inner.over (fun _ -> res ^. contents) body) res)
  }

(** A lens which exposes the trailing trivia of a term.

    When converting a term from a {!SimpleNode} to a {!Node}, we will use the position of the first
    trivial node. *)
let trailing_trivia =
  let get = function
    | SimpleNode _ -> []
    | Node { trailing_trivia = t; _ } -> t
  in
  let over f x =
    let t = f (get x) in
    match (x, t) with
    | SimpleNode _, [] -> x
    | SimpleNode { contents }, { Span.span; _ } :: _ ->
        Node { span; contents; trailing_trivia = t; leading_trivia = [] }
    | Node n, _ -> Node { n with trailing_trivia = t }
  in
  { get; over }

(** A lens which exposes the leading trivia of a term.

    When converting a term from a {!SimpleNode} to a {!Node}, we will use the position of the first
    trivial node. *)
let leading_trivia =
  let get = function
    | SimpleNode _ -> []
    | Node { leading_trivia = t; _ } -> t
  in
  let over f x =
    let t = f (get x) in
    match (x, t) with
    | SimpleNode _, [] -> x
    | SimpleNode { contents }, { Span.span; _ } :: _ ->
        Node { span; contents; leading_trivia = t; trailing_trivia = [] }
    | Node n, _ -> Node { n with leading_trivia = t }
  in
  { get; over }

(** Join two lists of trivial nodes together. While {!(\@)} will normally suffice for this,
    {!join_trivia} attempts to merge whitespace between adjacent nodes too. *)
let join_trivia xs ys : trivial Span.spanned list =
  match ys with
  | [] -> xs
  | { Span.value = Whitespace r; span = rs } :: ys' ->
      let is_space = function
        | ' ' | '\t' -> true
        | _ -> false
      in
      let rec go = function
        | [] -> ys
        | [ ({ Span.value = Whitespace l; span = ls } as x) ] ->
            if l = "" then ys
            else if is_space l.[String.length l - 1] then
              { Span.value = Whitespace (CCString.rdrop_while is_space l ^ r);
                span = Span.of_span2 ls rs
              }
              :: ys'
            else x :: ys
        | x :: xs -> x :: go xs
      in
      go xs
  | ys -> xs @ ys
