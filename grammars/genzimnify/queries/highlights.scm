; Syntax highlighting queries for Genzimnify (.gzim)

; ---------------------------------------------------------------- comments

(comment) @comment

; ---------------------------------------------------------------- literals

(number) @number
(string) @string

(f_string_start) @string.special
(f_string_content) @string.special
(f_string_end) @string.special

(glow_interpolation
  "{" @punctuation.special
  "}" @punctuation.special)

(fstring_spec) @attribute

(nocap) @constant.builtin
(cap) @constant.builtin
(ghost) @constant.builtin

; ---------------------------------------------------------------- keywords

[
  "let" "lock" "be" "be+" "be-" "be*" "be/" "be//" "be%" "be**"
  "=" "+=" "-=" "*=" "/=" "//=" "%=" "**="
] @keyword

["vibecheck" "or" "otherwise"] @keyword.conditional
["sus"] @keyword.conditional
["vibe" "for" "real" "up" "in" "dip" "next"] @keyword.repeat
["send" "it" "drop"] @keyword.return
["cook" "gives" "mini"] @keyword.function
["pull" "outta" "as"] @keyword.import
["f_around" "find_out" "no_matter_what" "throw" "shade"] @keyword.exception
["roll" "with"] @keyword
["on" "timing" "wait"] @keyword.coroutine
["worldwide" "localish"] @keyword.modifier
["cancel" "on" "god" "deadass" "clique" "new"] @keyword

; comparison / logical slang read as operators
["same as" "aint" "aint literally" "aint up in" "up in" "literally" "both" "either"] @keyword.operator


["fr"] @punctuation.special

; ---------------------------------------------------------------- functions

(cook_definition
  name: (identifier) @function)

(async_cook_definition
  name: (identifier) @function)

(function_call
  function: (identifier) @function.call)

(function_call
  function: (builtin_function) @function.builtin)

(call_up_expression
  function: (builtin_function) @function.builtin)

(call_up_expression
  function: (identifier) @function.call)

(function_call
  function: (attribute
    attribute: (identifier) @function.method.call))

(call_up_expression
  function: (attribute
    attribute: (identifier) @function.method.call))

(parameter
  name: (identifier) @variable.parameter)

(fam) @variable.builtin
(ancestor) @keyword

; ---------------------------------------------------------------- variables

(variable_declaration
  name: (identifier) @variable)

(assignment
  left: (identifier) @variable)

(for_real_statement
  targets: (loop_target
    (identifier) @variable))

(for_clause
  targets: (loop_target
    (identifier) @variable))

(import_target) @module

(cancel_statement
  (identifier) @variable)

(worldwide_statement
  (identifier) @variable)
(localish_statement
  (identifier) @variable)

; ---------------------------------------------------------------- types & cliques

(clique_definition
  name: (identifier) @type)

(clique_definition
  bases: (identifier) @type)

(builtin_type) @type.builtin

(generic_type
  name: (identifier) @type)

(find_out_clause
  type: (identifier) @type)

(throw_shade_statement
  (call_up_expression
    function: (identifier) @type))

; ---------------------------------------------------------------- attributes

(attribute
  attribute: (identifier) @property)

; ---------------------------------------------------------------- punctuation

["(" ")" "[" "]" "{" "}"] @punctuation.bracket
["," "." ":" "?"] @punctuation.delimiter
