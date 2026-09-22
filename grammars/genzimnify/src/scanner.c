/**
 * External scanner for tree-sitter-genzimnify.
 *
 * External tokens (order MUST match `externals` in grammar.js):
 *   0 NEWLINE         end of a logical line
 *   1 INDENT          opens an indented block
 *   2 DEDENT          closes an indented block (zero-length)
 *   3 F_STRING_START  glow"   (covers `glow` + opening quote(s))
 *   4 F_STRING_CONTENT  literal text between interpolations
 *   5 F_STRING_END    closing quote(s)
 */

#include "tree_sitter/parser.h"
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>

enum TokenType {
  NEWLINE,
  INDENT,
  DEDENT,
  F_STRING_START,
  F_STRING_CONTENT,
  FSTRING_ESCAPE,
  F_STRING_END,
};

#define MAX_INDENTS 48

typedef struct {
  int indents[MAX_INDENTS];
  unsigned indent_top;
  int in_fstring;      // 0 = not in fstring, 1 = after f_string_start
  char quote;          // quote char of the current fstring
  int triple;          // triple-quoted fstring?
  bool pending_end;    // glow"" : closing quote already consumed by START
  bool at_line_start;
} Scanner;

void *tree_sitter_genzimnify_external_scanner_create(void) {
  Scanner *s = calloc(1, sizeof(Scanner));
  s->indents[0] = 0;
  s->indent_top = 0;
  s->at_line_start = true;
  return s;
}

void tree_sitter_genzimnify_external_scanner_destroy(void *payload) {
  free(payload);
}

unsigned tree_sitter_genzimnify_external_scanner_serialize(void *payload, char *buffer) {
  Scanner *s = (Scanner *)payload;
  unsigned len = sizeof(Scanner);
  if (len > TREE_SITTER_SERIALIZATION_BUFFER_SIZE) len = TREE_SITTER_SERIALIZATION_BUFFER_SIZE;
  memcpy(buffer, s, len);
  return len;
}

void tree_sitter_genzimnify_external_scanner_deserialize(void *payload, const char *buffer, unsigned length) {
  Scanner *s = (Scanner *)payload;
  memset(s, 0, sizeof(Scanner));
  if (length > 0) {
    unsigned len = length < sizeof(Scanner) ? length : sizeof(Scanner);
    memcpy(s, buffer, len);
    if (s->indent_top >= MAX_INDENTS) s->indent_top = MAX_INDENTS - 1;
  }
  s->indents[0] = 0;
}

static bool is_space(int32_t c) {
  return c == ' ' || c == '\t' || c == '\r';
}

// ---------------------------------------------------------------- fstrings

static bool scan_fstring_start(Scanner *s, TSLexer *lexer) {
  if (lexer->lookahead != 'g') return false;
  lexer->advance(lexer, false);
  if (lexer->lookahead != 'l') return false;
  lexer->advance(lexer, false);
  if (lexer->lookahead != 'o') return false;
  lexer->advance(lexer, false);
  if (lexer->lookahead != 'w') return false;
  lexer->advance(lexer, false);
  if (lexer->lookahead != '"' && lexer->lookahead != '\'') return false;

  s->quote = lexer->lookahead;
  lexer->advance(lexer, false);

  if (lexer->lookahead == s->quote) {
    lexer->advance(lexer, false);  // second quote
    if (lexer->lookahead == s->quote) {
      lexer->advance(lexer, false);  // third quote -> triple
      s->triple = 1;
      s->pending_end = false;
    } else {
      // empty string: glow"" — closing quote already consumed
      s->triple = 0;
      s->pending_end = true;
    }
  } else {
    s->triple = 0;
    s->pending_end = false;
  }

  lexer->mark_end(lexer);
  s->in_fstring = 1;
  s->at_line_start = false;
  lexer->result_symbol = F_STRING_START;
  return true;
}

static bool scan_fstring_escape(Scanner *s, TSLexer *lexer) {
  // at a brace; doubled braces are literal content, single braces belong to
  // an interpolation. mark_end BEFORE advancing so the token never commits
  // past the brace.
  bool is_left = lexer->lookahead == '{';
  lexer->advance(lexer, false);
  if ((lexer->lookahead == '{' && is_left) ||
      (lexer->lookahead == '}' && !is_left)) {
    lexer->advance(lexer, false);
    lexer->mark_end(lexer);
    s->at_line_start = false;
    lexer->result_symbol = FSTRING_ESCAPE;
    return true;
  }
  return false;
}

static bool scan_fstring_content(Scanner *s, TSLexer *lexer) {
  bool has_content = false;
  while (lexer->lookahead != 0) {
    int32_t c = lexer->lookahead;
    if (c == s->quote) break;  // emit END on the next call
    if (c == '{' || c == '}') {
      // emit the content scanned so far; the brace itself stays for the
      // next token (escape check or interpolation)
      lexer->mark_end(lexer);
      lexer->result_symbol = F_STRING_CONTENT;
      return has_content;
    }
    if (c == '\\') {
      lexer->advance(lexer, false);
      if (lexer->lookahead != 0) lexer->advance(lexer, false);
      has_content = true;
      continue;
    }
    lexer->advance(lexer, false);
    has_content = true;
  }
  if (!has_content) return false;
  lexer->mark_end(lexer);
  s->at_line_start = false;
  lexer->result_symbol = F_STRING_CONTENT;
  return true;
}

static bool scan_fstring_end(Scanner *s, TSLexer *lexer) {
  if (s->pending_end) {
    // closing quote was already consumed as part of START
    s->pending_end = false;
    s->in_fstring = 0;
    lexer->mark_end(lexer);
    lexer->result_symbol = F_STRING_END;
    return true;
  }
  if (lexer->lookahead != s->quote) return false;
  lexer->advance(lexer, false);
  if (s->triple) {
    if (lexer->lookahead == s->quote) {
      lexer->advance(lexer, false);
      if (lexer->lookahead == s->quote) {
        lexer->advance(lexer, false);
      }
    }
  }
  s->triple = 0;
  s->in_fstring = 0;
  s->at_line_start = false;
  lexer->mark_end(lexer);
  lexer->result_symbol = F_STRING_END;
  return true;
}

// ---------------------------------------------------------------- main scan

bool tree_sitter_genzimnify_external_scanner_scan(void *payload, TSLexer *lexer, const bool *valid_symbols) {
  Scanner *s = (Scanner *)payload;

  // fstring phases
  if (valid_symbols[F_STRING_START] && !s->in_fstring) {
    if (scan_fstring_start(s, lexer)) return true;
  }
  if (s->in_fstring) {
    // escape/interpolation phase
    if (valid_symbols[F_STRING_END] &&
        (s->pending_end || lexer->lookahead == s->quote)) {
      return scan_fstring_end(s, lexer);
    }
    if (valid_symbols[FSTRING_ESCAPE] &&
        (lexer->lookahead == '{' || lexer->lookahead == '}')) {
      // attempt the doubled-brace escape; on failure return false so the
      // lexer position is restored and the internal lexer can match '{'
      // as the start of a glow_interpolation
      if (scan_fstring_escape(s, lexer)) return true;
      return false;
    }
    if (valid_symbols[F_STRING_CONTENT]) {
      return scan_fstring_content(s, lexer);
    }
    return false;
  }

  if (lexer->lookahead == '\n') {
    if (!valid_symbols[NEWLINE]) return false;
    lexer->advance(lexer, false);
    lexer->mark_end(lexer);
    s->at_line_start = true;
    lexer->result_symbol = NEWLINE;
    return true;
  }

  if (lexer->lookahead == 0) {
    // EOF: unwind indentation
    if (valid_symbols[DEDENT] && s->indent_top > 0) {
      s->indent_top--;
      s->at_line_start = true;
      lexer->mark_end(lexer);
      lexer->result_symbol = DEDENT;
      return true;
    }
    return false;
  }

  if (s->at_line_start && lexer->lookahead != '\n' && lexer->lookahead != 0) {
    // start of a content line: measure indentation (the first char may or
    // may not be whitespace)
    int width = 0;
    lexer->mark_end(lexer);  // zero-length anchor for DEDENT
    while (is_space(lexer->lookahead)) {
      width += lexer->lookahead == '\t' ? 4 : (lexer->lookahead == '\r' ? 0 : 1);
      lexer->advance(lexer, false);
    }

    if (lexer->lookahead == '#') {
      // comment-only line: the comment extra consumes the text; the newline
      // is handled on the next scan call
      s->at_line_start = true;
      return false;
    }

    if (lexer->lookahead == 0) {
      if (valid_symbols[DEDENT] && s->indent_top > 0) {
        s->indent_top--;
        s->at_line_start = true;
        lexer->result_symbol = DEDENT;
        return true;
      }
      return false;
    }

    int prev = s->indents[s->indent_top];
    if (width > prev && valid_symbols[INDENT]) {
      if (s->indent_top + 1 >= MAX_INDENTS) return false;
      s->indents[++s->indent_top] = width;
      lexer->mark_end(lexer);  // INDENT covers the leading whitespace
      s->at_line_start = false;
      lexer->result_symbol = INDENT;
      return true;
    }
    if (width < prev && valid_symbols[DEDENT]) {
      s->indent_top--;
      s->at_line_start = true;  // still at the start of the line
      lexer->result_symbol = DEDENT;
      return true;
    }
    // same indent level: let the internal lexer take over
    s->at_line_start = false;
    return false;
  }

  return false;
}
