/**
 * tree-sitter grammar for Genzimnify (.gzim)
 * Python semantics, Gen Z surface syntax.
 */

const PREC = {
  OR: 10,
  AND: 20,
  NOT: 25,
  COMPARE: 30,
  PLUS: 40,
  TIMES: 50,
  UNARY: 55,
  POWER: 70,
  CALL: 100,
};

module.exports = grammar({
  name: 'genzimnify',

  word: $ => $.identifier,

  extras: $ => [
    /[ \t\r]/,
    $.comment,
  ],

  externals: $ => [
    $._newline,
    $._indent,
    $._dedent,
    $.f_string_start,
    $.f_string_content,
    $.fstring_escape,
    $.f_string_end,
  ],

  supertypes: $ => [
    $._expression,
    $._simple_statement,
  ],

  conflicts: $ => [
    [$._expression, $._primary_expression],
    [$._assignable, $._primary_expression],
    [$.block],
  ],

  rules: {
    source_file: $ => repeat(choice($._newline, $._statement)),

    _statement: $ => choice(
      $._simple_statement_line,
      $._compound_statement,
    ),

    _simple_statement_line: $ => seq(
      $._simple_statement,
      repeat(seq('fr', $._simple_statement)),
      optional('fr'),
      $._newline,
    ),

    block: $ => choice(
      seq(
        $._newline,
        $._indent,
        repeat(choice($._newline, $._statement)),
        $._dedent,
      ),
      seq(
        $._simple_statement,
        repeat(seq('fr', $._simple_statement)),
        optional('fr'),
      ),
    ),

    // ------------------------------------------------------------ simple statements

    _simple_statement: $ => choice(
      $.variable_declaration,
      $.assignment,
      $.expression_statement,
      $.send_it,
      $.drop_statement,
      $.dip,
      $.next,
      $.deadass,
      $.throw_shade_statement,
      $.pull_up_import,
      $.outta_import,
      $.cancel_statement,
      $.on_god_statement,
      $.worldwide_statement,
      $.localish_statement,
    ),

    variable_declaration: $ => seq(
      choice('let', 'lock'),
      field('name', $.identifier),
      optional($.type_annotation),
      'be',
      field('value', $._expression),
      optional($.type_annotation),
    ),

    assignment: $ => seq(
      field('left', $._assignable),
      choice(
        seq(choice('be', '='), field('right', $._expression)),
        seq(
          choice(
            'be+', 'be-', 'be*', 'be/', 'be//', 'be%', 'be**',
            '+=', '-=', '*=', '/=', '//=', '%=', '**=',
          ),
          field('right', $._expression),
        ),
      ),
    ),

    _assignable: $ => choice(
      $.identifier,
      $.fam,
      $.attribute,
      $.subscript,
      $.crew,
    ),

    expression_statement: $ => $._expression,

    send_it: $ => prec.right(seq('send', 'it', optional($._expression))),

    drop_statement: $ => prec.right(seq('drop', optional($._expression))),

    dip: $ => 'dip',
    next: $ => 'next',
    deadass: $ => 'deadass',

    throw_shade_statement: $ => prec.right(seq('throw', 'shade', optional($._expression))),

    dotted_name: $ => seq($.identifier, repeat(seq('.', $.identifier))),

    import_target: $ => choice($.identifier, 'all'),

    pull_up_import: $ => seq(
      'pull', 'up',
      field('module', $.dotted_name),
      optional(seq('as', field('alias', $.identifier))),
    ),

    outta_import: $ => seq(
      'outta',
      field('module', $.dotted_name),
      'pull', 'up',
      field('names', $.import_names),
    ),

    import_names: $ => seq(
      $.import_target,
      optional(seq('as', field('alias', $.identifier))),
      repeat(seq(
        ',',
        $.import_target,
        optional(seq('as', field('alias', $.identifier))),
      )),
    ),

    cancel_statement: $ => seq(
      'cancel',
      $._assignable,
      repeat(seq(',', $._assignable)),
    ),

    on_god_statement: $ => seq(
      'on', 'god',
      field('condition', $._expression),
      optional(seq(',', field('message', $._expression))),
    ),

    worldwide_statement: $ => seq(
      'worldwide',
      $.identifier,
      repeat(seq(',', $.identifier)),
    ),

    localish_statement: $ => seq(
      'localish',
      $.identifier,
      repeat(seq(',', $.identifier)),
    ),

    // ------------------------------------------------------------ compound statements

    _compound_statement: $ => choice(
      $.vibecheck_statement,
      $.vibe_statement,
      $.for_real_statement,
      $.cook_definition,
      $.async_cook_definition,
      $.clique_definition,
      $.f_around_statement,
      $.roll_with_statement,
      $.fit_check_statement,
    ),

    async_cook_definition: $ => seq(
      'on', 'timing',
      'cook',
      field('name', choice($.identifier, 'new')),
      '(',
      optional($.parameters),
      ')',
      optional($.gives),
      ':',
      field('body', $.block),
    ),

    vibecheck_statement: $ => seq(
      'vibecheck',
      field('condition', $._expression),
      ':',
      field('body', $.block),
      repeat(seq('or', field('condition', $._expression), ':', field('body', $.block))),
      optional(seq('otherwise', ':', field('body', $.block))),
    ),

    vibe_statement: $ => seq(
      'vibe',
      field('condition', $._expression),
      ':',
      field('body', $.block),
    ),

    loop_target: $ => choice($.identifier, $.fam),

    for_real_statement: $ => seq(
      'for', 'real',
      field('targets', $._loop_targets),
      'up', 'in',
      field('value', $._expression),
      ':',
      field('body', $.block),
    ),

    _loop_targets: $ => choice(
      $.loop_target,
      seq('(', $.loop_target, repeat(seq(',', $.loop_target)), ')'),
      seq($.loop_target, repeat(seq(',', $.loop_target))),
    ),

    parameters: $ => seq(
      $.parameter,
      repeat(seq(',', $.parameter)),
      optional(','),
    ),

    parameter: $ => seq(
      optional(choice('*', '**')),
      field('name', choice($.identifier, $.fam)),
      optional($.type_annotation),
      optional(seq(choice('be', '='), field('default', $._expression))),
    ),

    type_annotation: $ => seq('as', field('type', $._type)),

    gives: $ => seq('gives', field('type', $._type)),

    cook_definition: $ => seq(
      'cook',
      field('name', choice($.identifier, 'new')),
      '(',
      optional($.parameters),
      ')',
      optional($.gives),
      ':',
      field('body', $.block),
    ),

    clique_definition: $ => seq(
      'clique',
      field('name', $.identifier),
      optional(seq(
        '(',
        optional(seq(
          field('bases', $._expression),
          repeat(seq(',', field('bases', $._expression))),
          optional(','),
        )),
        ')',
      )),
      ':',
      field('body', $.block),
    ),

    f_around_statement: $ => seq(
      'f_around', ':',
      field('body', $.block),
      repeat($.find_out_clause),
      optional(seq('otherwise', ':', field('else_body', $.block))),
      optional(seq('no_matter_what', ':', field('finally_body', $.block))),
    ),

    find_out_clause: $ => seq(
      'find_out',
      field('type', optional($._expression)),
      optional(seq('as', field('alias', $.identifier))),
      ':',
      field('body', $.block),
    ),

    roll_with_statement: $ => seq(
      'roll', 'with',
      $.with_item,
      repeat(seq(',', $.with_item)),
      ':',
      field('body', $.block),
    ),

    with_item: $ => seq(
      field('value', $._expression),
      optional(seq('as', field('alias', $.identifier))),
    ),

    fit_check_statement: $ => seq(
      'fit', 'check',
      field('subject', $._expression),
      ':',
      $._newline,
      $._indent,
      repeat($.fit_case),
      optional(seq('otherwise', ':', field('default', $.block))),
      $._dedent,
    ),

    fit_case: $ => seq(
      'fit',
      field('pattern', $._pattern),
      ':',
      field('body', $.block),
    ),

    _pattern: $ => choice(
      $.number,
      $.string,
      $.identifier,
      $.list,
      $.crew,
      $.attribute,
      $.parenthesized_expression,
      seq('-', $.number),
      'ghost',
      'nocap',
      'cap',
    ),

    // ------------------------------------------------------------ expressions

    _expression: $ => choice(
      $.identifier,
      $.fam,
      $.ancestor,
      $.nocap,
      $.cap,
      $.ghost,
      $.number,
      $.string,
      $.fstring,
      $.list,
      $.set,
      $.dictionary,
      $.crew,
      $.parenthesized_expression,
      $.attribute,
      $.subscript,
      $.function_call,
      $.call_up_expression,
      $.not_expression,
      $.unary_expression,
      $.binary_expression,
      $.await_expression,
      $.drop_expression,
      $.mini_vibe,
    ),

    nocap: $ => 'nocap',
    cap: $ => 'cap',
    ghost: $ => 'ghost',
    fam: $ => 'fam',
    ancestor: $ => 'ancestor',

    number: $ => token(choice(
      seq(
        /[0-9][0-9_]*/,
        optional(choice(
          seq('.', /[0-9](_?[0-9])*/),
          seq(/[eE]/, optional(/[+-]/), /[0-9][0-9_]*/),
          seq('.', /[0-9](_?[0-9])*/, /[eE]/, optional(/[+-]/), /[0-9][0-9_]*/),
        )),
      ),
      seq('.', /[0-9](_?[0-9])*/),
    )),

    string: $ => token(choice(
      /"([^"\\\n]|\\.)*"/,
      /'([^'\\\n]|\\.)*'/,
    )),

    fstring: $ => seq(
      $.f_string_start,
      repeat(choice($.f_string_content, $.fstring_escape, $.glow_interpolation)),
      $.f_string_end,
    ),

    fstring_escape: $ => 'x', // external: covers a doubled `{{` or `}}`

    glow_interpolation: $ => seq(
      '{',
      optional(field('expression', $._expression)),
      optional($.fstring_spec),
      '}',
    ),

    fstring_spec: $ => token(/[!:][^{}"'\\\n]*/),

    list: $ => choice(
      seq('[', ']'),
      seq(
        '[',
        choice(
          seq($._expression, repeat(seq(',', $._expression)), optional(',')),
          seq($._expression, repeat1($.for_clause)),
        ),
        ']',
      ),
    ),

    for_clause: $ => seq(
      'for', 'real',
      field('targets', $._loop_targets),
      'up', 'in',
      field('value', $._expression),
      repeat(seq('sus', field('filter', $._expression))),
    ),

    set: $ => seq(
      '{',
      $._collection_elements,
      '}',
    ),

    dictionary: $ => seq(
      '{',
      optional(seq(
        $.pair,
        repeat(seq(',', $.pair)),
        optional(','),
      )),
      '}',
    ),

    pair: $ => seq(
      field('key', $._expression),
      ':',
      field('value', $._expression),
    ),

    parenthesized_expression: $ => prec(1, seq(
      '(',
      $._expression,
      ')',
    )),

    crew: $ => seq(
      '(',
      optional($._collection_elements),
      ')',
    ),

    _collection_elements: $ => seq(
      choice($._expression, $.list_splat, $.dict_splat),
      repeat(seq(',', choice($._expression, $.list_splat, $.dict_splat))),
      optional(','),
    ),

    attribute: $ => prec(PREC.CALL, seq(
      field('object', $._primary_expression),
      '.',
      field('attribute', $._attr_name),
    )),

    _attr_name: $ => choice(
      $.identifier,
      'new', 'ghost', 'nocap', 'cap', 'dip', 'next', 'deadass', 'drop',
      'sus', 'gives', 'as', 'or', 'both', 'either', 'aint', 'nah',
      'literally', 'ancestor', 'fam', 'yap', 'yap back',
      'how many', 'add up', 'round up', 'index up', 'vibe check',
    ),

    _primary_expression: $ => choice(
      $.identifier,
      $.fam,
      $.ancestor,
      $.nocap,
      $.cap,
      $.ghost,
      $.number,
      $.string,
      $.fstring,
      $.list,
      $.set,
      $.dictionary,
      $.crew,
      $.parenthesized_expression,
      $.attribute,
      $.subscript,
      $.function_call,
      $.builtin_function,
    ),

    builtin_function: $ => choice(
      'how many', 'vibe check', 'add up', 'round up', 'index up',
      'yap', 'yap back',
    ),

    subscript: $ => prec(PREC.CALL, seq(
      field('object', $._primary_expression),
      '[',
      $._subscript_body,
      ']',
    )),

    _subscript_body: $ => choice(
      $._expression,
      $.slice,
    ),

    slice: $ => seq(
      optional(field('start', $._expression)),
      ':',
      optional(field('stop', $._expression)),
      optional(seq(':', optional(field('step', $._expression)))),
    ),

    function_call: $ => prec(PREC.CALL, seq(
      field('function', $._primary_expression),
      '(',
      optional($.argument_list),
      ')',
    )),

    argument_list: $ => seq(
      $._argument,
      repeat(seq(',', $._argument)),
      optional(','),
    ),

    _argument: $ => choice(
      $._expression,
      $.keyword_argument,
      $.list_splat,
      $.dict_splat,
    ),

    keyword_argument: $ => seq(
      field('name', $.identifier),
      choice('be', '='),
      field('value', $._expression),
    ),

    list_splat: $ => seq('*', $._expression),
    dict_splat: $ => seq('**', $._expression),

    call_up_expression: $ => prec(PREC.CALL, seq(
      'call', 'up',
      field('function', $._primary_expression),
      '(',
      optional($.argument_list),
      ')',
      'yo',
    )),

    not_expression: $ => prec(PREC.NOT, seq('aint', $._expression)),

    unary_expression: $ => prec(PREC.UNARY, seq(
      choice('-', '+'),
      $._expression,
    )),

    binary_expression: $ => choice(
      prec.left(PREC.OR, seq(
        field('left', $._expression),
        field('operator', choice('or', 'either')),
        field('right', $._expression),
      )),
      prec.left(PREC.AND, seq(
        field('left', $._expression),
        field('operator', choice('both', 'and')),
        field('right', $._expression),
      )),
      prec.left(PREC.COMPARE, seq(
        field('left', $._expression),
        field('operator', choice(
          '==', '!=', 'nah', '<', '>', '<=', '>=',
          'same as', 'up in', 'aint up in', 'literally', 'aint literally',
        )),
        field('right', $._expression),
      )),
      prec.left(PREC.PLUS, seq(
        field('left', $._expression),
        field('operator', choice('+', '-')),
        field('right', $._expression),
      )),
      prec.left(PREC.TIMES, seq(
        field('left', $._expression),
        field('operator', choice('*', '/', '//', '%')),
        field('right', $._expression),
      )),
      prec.right(PREC.POWER, seq(
        field('left', $._expression),
        field('operator', '**'),
        field('right', $._expression),
      )),
    ),

    await_expression: $ => prec(PREC.UNARY, seq('wait', 'up', $._expression)),

    drop_expression: $ => prec.right(5, seq('drop', optional($._expression))),

    mini_vibe: $ => seq(
      'mini', 'vibe',
      '(',
      optional($.parameters),
      ')',
      ':',
      field('body', $._expression),
    ),

    // ------------------------------------------------------------ types

    _type: $ => prec.right(seq($._type_atom, repeat(seq('or', $._type_atom)))),

    _type_atom: $ => prec.right(seq(
      field('name', choice(
        $.builtin_type,
        $.identifier,
      )),
      optional($.generic_type),
      repeat('?'),
    )),

    builtin_type: $ => choice(
      'num', 'drip', 'text', 'truth', 'ghost', 'whatever',
      'stack', 'map', 'squad', 'crew',
    ),

    generic_type: $ => seq(
      '[',
      optional(seq($._type, repeat(seq(',', $._type)))),
      ']',
    ),

    // ------------------------------------------------------------ names

    identifier: $ => token(prec(-1, /[a-zA-Z_][a-zA-Z0-9_]*/)),

    // ------------------------------------------------------------ comments

    comment: $ => token(choice(
      /#[^\n]*/,
      seq(
        '#[[',
        repeat(choice(
          /[^\]]/,
          seq(']', /[^\]]/),
          seq(']]', /[^#]/),
        )),
        ']]#',
      ),
    )),
  },
});
