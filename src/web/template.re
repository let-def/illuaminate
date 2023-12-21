open IlluaminateCore;
module JsHtml =
  Html.Make({
    open Js_of_ocaml;
    type event_handler = Js.t(Dom_html.event) => Js.t(bool);
  });
include JsHtml;

let level: Error.level => string =
  level =>
    switch (level) {
    | Critical => "critical"
    | Error => "error"
    | Warning => "warning"
    | Note => "note"
    };

let partition_string = (start, length, str) => {
  let str_len = String.length(str);
  if (start >= str_len) {
    (
      str,
      None,
      "" // If we start before the string length, just bail entirely.
    );
  } else if (start + length <= 0) {
    ("", None, str);
  } else {
    let start = max(0, start);
    let length = min(str_len - start, length);
    (
      String.sub(str, 0, start),
      Some(String.sub(str, start, length)),
      String.sub(str, start + length, str_len - start - length),
    );
  };
};

let source_line = (source, span, message) => {
  let start_line = Span.start_line(span);
  let start_col = Span.start_col(span);
  let finish_line = Span.finish_line(span);
  let finish_col = Span.finish_col(span);

  let bol = Span.start_bol(span);
  let line_end =
    String.index_from_opt(source, bol, '\n')
    |> Option.value(~default=String.length(source));
  let line = String.sub(source, bol, line_end - bol);

  let length =
    if (finish_line == start_line) {
      finish_col - start_col + 1;
    } else {
      String.length(line) - start_col + 1;
    };
  let (before, contents, after) =
    partition_string(start_col - 1, length, line);

  <div class_="error-line">
    <div class_="error-line-no"> {str(string_of_int(start_line))} </div>
    <div class_="error-line-body">
      <div class_="error-line-str">
        {str(before)}
        <em> {Option.fold(~none=str(" "), ~some=str, contents)} </em>
        {str(after)}
      </div>
      {switch (message) {
       | None => nil
       | Some(msg) =>
         <div class_="error-message">
           {str(
              Format.asprintf(
                "%s^ %a",
                String.make(start_col - 1, ' '),
                msg,
                (),
              ),
            )}
         </div>
       }}
    </div>
  </div>;
};

let annotation = (source, annotation) => {
  switch (annotation) {
  | Error.Error.Message(msg) =>
    <div class_="error-message"> {str(Format.asprintf("%a", msg, ()))} </div>
  | Error.Error.Annotation(span, msg) => source_line(source, span, msg)
  };
};

let error = (source, {Error.Error.span, message, tag, annotations}) => {
  <div class_={"error error-" ++ level(tag.level)}>
    <div class_="error-message">
      {Format.asprintf("%a [%s]", message, (), tag.name) |> str}
    </div>
    {switch (annotations) {
     | [] => source_line(source, span, None)
     | _ => List.map(annotation(source), annotations) |> many
     }}
  </div>;
};

let mk_minify = minify => {
  <button onClick=minify class_="btn-minify" title="Minify this source code.">
    {str("Minify")}
  </button>;
};

let some_errors = (program, ~minify, ~fix=?, errors) => {
  let main =
    List.map(
      ({Error.Error.span, _} as err) => {
        let bol = Span.start_bol(span);
        let line_end =
          String.index_from_opt(program, bol, '\n')
          |> Option.value(~default=String.length(program));
        let line = String.sub(program, bol, line_end - bol);
        error(line, err);
      },
      errors,
    );
  let (errors, warnings) =
    List.fold_left(
      ((errors, warnings), {Error.Error.tag, _}) =>
        switch (tag.level) {
        | Critical
        | Error => (errors + 1, warnings)
        | Warning
        | Note => (errors, warnings + 1)
        },
      (0, 0),
      errors,
    );
  many([
    <div class_="error-summary error-some">
      {str(Printf.sprintf("✘ %d errors and %d warnings", errors, warnings))}
      {switch (fix) {
       | Some(fix) =>
         <button
           onClick=fix
           class_="error-fix"
           title="Attempt to fix as many problems as possible.">
           {str("Fix all")}
         </button>
       | None => nil
       }}
      {mk_minify(minify)}
    </div>,
    ...main,
  ]);
};

let no_errors = (~minify) =>
  <div class_="error-summary error-none">
    {str("✓ No errors")}
    {mk_minify(minify)}
  </div>;
