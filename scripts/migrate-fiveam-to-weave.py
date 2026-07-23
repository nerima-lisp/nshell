#!/usr/bin/env python3
"""Deterministic FiveAM -> cl-weave migrator for nshell test files.

Transforms, preserving all comments and formatting outside the rewritten spans:
  (in-suite X)            -> dropped (records the current describe name)
  (def-suite ...)         -> dropped
  (test NAME body...)     -> (it "NAME" body...), grouped under (describe "X" ...)
  (is FORM)               -> (expect ...) with matcher inference
  (signals COND body...)  -> (expect (lambda () body...) :to-throw 'COND)

`is`/`signals` are rewritten wherever they appear (including inside helper
macros and let/loop/dolist bodies), via a full recursive walk.
"""
import sys

WS = " \t\n\r\f"

# predicate -> (matcher, arity)
MATCHERS = {
    "eq": (":to-be", 2),
    "eql": (":to-be", 2),
    "=": (":to-equal", 2),
    "equal": (":to-equal", 2),
    "equalp": (":to-equalp", 2),
    "string=": (":to-equal", 2),
    "char=": (":to-equal", 2),
    "null": (":to-be-null", 1),
    "not": (":to-be-falsy", 1),
    "typep": (":to-be-type-of", 2),
    "<": (":to-be-less-than", 2),
    ">": (":to-be-greater-than", 2),
    "<=": (":to-be-less-than-or-equal", 2),
    ">=": (":to-be-greater-than-or-equal", 2),
}


class Scanner:
    def __init__(self, s):
        self.s = s
        self.n = len(s)

    def skip_ws_comments(self, i):
        """Advance over whitespace, ; line comments, and #| |# block comments."""
        s, n = self.s, self.n
        while i < n:
            c = s[i]
            if c in WS:
                i += 1
            elif c == ";":
                while i < n and s[i] != "\n":
                    i += 1
            elif c == "#" and i + 1 < n and s[i + 1] == "|":
                depth = 1
                i += 2
                while i < n and depth > 0:
                    if s[i] == "#" and i + 1 < n and s[i + 1] == "|":
                        depth += 1
                        i += 2
                    elif s[i] == "|" and i + 1 < n and s[i + 1] == "#":
                        depth -= 1
                        i += 2
                    else:
                        i += 1
            else:
                break
        return i

    def read_string(self, i):
        s, n = self.s, self.n
        assert s[i] == '"'
        i += 1
        while i < n:
            if s[i] == "\\":
                i += 2
            elif s[i] == '"':
                return i + 1
            else:
                i += 1
        return i

    def read_char(self, i):
        """#\\x or #\\Newline -> end index."""
        s, n = self.s, self.n
        # s[i:i+2] == '#\\'
        i += 2
        if i < n:
            i += 1  # always consume at least one char (the char itself)
        # named char: continue over alphanumerics/-
        while i < n and (s[i].isalnum() or s[i] == "-"):
            i += 1
        return i

    def read_atom(self, i):
        """Read a plain token up to a delimiter."""
        s, n = self.s, self.n
        if s[i] == "|":  # |vertical bar symbol|
            i += 1
            while i < n and s[i] != "|":
                if s[i] == "\\":
                    i += 2
                else:
                    i += 1
            return i + 1 if i < n else i
        while i < n and s[i] not in WS and s[i] not in "()\";'`,":
            if s[i] == "|":
                # embedded |...|
                i += 1
                while i < n and s[i] != "|":
                    i += 1
                i += 1
            else:
                i += 1
        return i

    def read_form(self, i):
        """Return end index (exclusive) of the form beginning at i (no leading ws)."""
        s, n = self.s, self.n
        c = s[i]
        if c in "([":
            return self.read_list(i)
        if c == '"':
            return self.read_string(i)
        if c in "'`":
            j = self.skip_ws_comments(i + 1)
            return self.read_form(j)
        if c == ",":
            j = i + 1
            if j < n and s[j] == "@":
                j += 1
            j = self.skip_ws_comments(j)
            return self.read_form(j)
        if c == "#":
            c2 = s[i + 1] if i + 1 < n else ""
            if c2 == "\\":
                return self.read_char(i)
            if c2 == "'":
                j = self.skip_ws_comments(i + 2)
                return self.read_form(j)
            if c2 in "([":
                return self.read_list(i + 1)
            if c2 == ".":
                j = self.skip_ws_comments(i + 2)
                return self.read_form(j)
            if c2 in "+-":
                j = self.read_form(self.skip_ws_comments(i + 2))  # feature
                return self.read_form(self.skip_ws_comments(j))   # guarded form
            # #:sym, #p"...", #xNN, #S(...), #C(...): read '#' + optional letters,
            # then if a list/string follows, include it.
            j = i + 1
            while j < n and (s[j].isalnum() or s[j] == ":"):
                j += 1
            if j < n and s[j] in '("':
                return self.read_form(j)
            return j
        return self.read_atom(i)

    def read_list(self, i):
        s, n = self.s, self.n
        assert s[i] in "(["
        close = ")" if s[i] == "(" else "]"
        i += 1
        while i < n:
            i = self.skip_ws_comments(i)
            if i >= n:
                break
            if s[i] in ")]":
                return i + 1
            i = self.read_form(i)
        return i

    def children(self, start, end):
        """For list span [start,end) return list of (cs,ce) child form spans."""
        s = self.s
        i = start + 1  # after '('
        out = []
        while i < end - 1:
            i = self.skip_ws_comments(i)
            if i >= end - 1 or s[i] in ")]":
                break
            j = self.read_form(i)
            out.append((i, j))
            i = j
        return out

    def head_symbol(self, start, end):
        """Lowercased head token text of the list at [start,end), or None."""
        ch = self.children(start, end)
        if not ch:
            return None
        cs, ce = ch[0]
        return self.s[cs:ce].lower()


def strip_quote_prefix(sc, s, e):
    """If span is a quote/backquote-prefixed form, return inner atom text w/o quote."""
    return sc.s[s:e]


def transform_is(sc, start, end):
    """Rewrite an (is ...) list span into an (expect ...) string."""
    s = sc.s
    ch = sc.children(start, end)
    # ch[0] is 'is'. The asserted form is ch[1]. Extra args (reason) dropped.
    if len(ch) < 2:
        return s[start:end]
    tests, teste = ch[1]
    # transform any nested is/signals inside the asserted form first
    inner = transform_form(sc, tests, teste)
    # Try matcher inference when the asserted form is (PRED a b...)
    if s[tests] == "(":
        pch = sc.children(tests, teste)
        if pch:
            phs, phe = pch[0]
            pred = s[phs:phe].lower()
            args = pch[1:]
            if pred in MATCHERS:
                matcher, arity = MATCHERS[pred]
                if len(args) == arity:
                    if arity == 1:
                        a = transform_form(sc, *args[0])
                        if pred == "not":
                            return f"(expect {a} :to-be-falsy)"
                        return f"(expect {a} {matcher})"
                    else:
                        a = transform_form(sc, *args[0])
                        b = transform_form(sc, *args[1])
                        return f"(expect {a} {matcher} {b})"
    # Fallback: truthy assertion over the (possibly transformed) inner form.
    return f"(expect {inner} :to-be-truthy)"


def transform_signals(sc, start, end):
    """(signals COND body...) -> (expect (lambda () body...) :to-throw 'COND)."""
    s = sc.s
    ch = sc.children(start, end)
    if len(ch) < 2:
        return s[start:end]
    conds, conde = ch[1]
    cond = s[conds:conde]
    body_spans = ch[2:]
    if not body_spans:
        body = ""
    else:
        b0 = body_spans[0][0]
        bl = body_spans[-1][1]
        body = transform_region(sc, b0, bl)
    return f"(expect (lambda () {body}) :to-throw '{cond})"


def transform_region(sc, start, end):
    """Transform a run of forms/gaps in [start,end), preserving inter-form text."""
    s = sc.s
    out = []
    i = start
    while i < end:
        j = sc.skip_ws_comments(i)
        out.append(s[i:j])  # preserve whitespace/comments
        if j >= end:
            break
        if s[j] in ")]":
            out.append(s[j])
            i = j + 1
            continue
        k = sc.read_form(j)
        if k > end:
            k = end
        out.append(transform_form(sc, j, k))
        i = k
    return "".join(out)


def transform_form(sc, start, end):
    """Recursively transform a single form span, returning new text."""
    s = sc.s
    c = s[start]
    # prefixes: emit and recurse into the following form
    if c in "'`":
        inner_start = sc.skip_ws_comments(start + 1)
        return s[start:inner_start] + transform_form(sc, inner_start, end)
    if c == ",":
        j = start + 1
        if j < end and s[j] == "@":
            j += 1
        inner_start = sc.skip_ws_comments(j)
        return s[start:inner_start] + transform_form(sc, inner_start, end)
    if c == "#":
        c2 = s[start + 1] if start + 1 < end else ""
        if c2 == "'":
            inner_start = sc.skip_ws_comments(start + 2)
            return s[start:inner_start] + transform_form(sc, inner_start, end)
        if c2 == "(":  # vector #(...): keep '#(' and transform elements
            return s[start:start + 2] + transform_children_body(sc, start + 1, end)
        if c2 in "+-":
            # #+feature / #-feature: keep the reader test verbatim, but recurse
            # into the guarded form so is/signals inside it are transformed.
            feat_end = sc.read_form(sc.skip_ws_comments(start + 2))
            guard_start = sc.skip_ws_comments(feat_end)
            return s[start:guard_start] + transform_form(sc, guard_start, end)
        # other # forms (#\char, #:sym, #p"...", ...): leave verbatim
        return s[start:end]
    if c in "([":
        head = sc.head_symbol(start, end)
        if head == "is":
            return transform_is(sc, start, end)
        if head == "signals":
            return transform_signals(sc, start, end)
        # generic list: rebuild, transforming children, preserving gaps
        return s[start] + transform_children_body(sc, start, end)
    # atom / string / char
    return s[start:end]


def transform_children_body(sc, start, end):
    """Transform inside a list that began at `start` ('('), up to and incl ')'."""
    s = sc.s
    out = []
    i = start + 1
    while i < end:
        j = sc.skip_ws_comments(i)
        out.append(s[i:j])
        if j >= end:
            break
        if s[j] in ")]":
            out.append(s[j])
            i = j + 1
            # copy any trailing text up to end
            if i < end:
                out.append(s[i:end])
            return "".join(out)
        k = sc.read_form(j)
        out.append(transform_form(sc, j, k))
        i = k
    return "".join(out)


def indent_block(text, prefix="  "):
    """Indent each code line by prefix, WITHOUT touching newlines that fall
    inside string literals or comments (indenting a multi-line string literal
    would corrupt its contents)."""
    out = []
    n = len(text)
    i = 0
    in_string = False
    in_comment = False
    line_start = True
    while i < n:
        c = text[i]
        if line_start:
            # Only indent a line that begins outside a string and is not blank.
            if not in_string and c not in "\n\r":
                out.append(prefix)
            line_start = False
        # Character literal #\x — copy verbatim so a #\" does not open a string.
        if (not in_string and not in_comment
                and c == "#" and i + 1 < n and text[i + 1] == "\\"):
            out.append(text[i:i + 3])
            i += 3
            continue
        if in_string:
            if c == "\\" and i + 1 < n:
                out.append(text[i:i + 2])
                i += 2
                continue
            if c == '"':
                in_string = False
        elif in_comment:
            pass  # comment ends at newline (handled below)
        else:
            if c == '"':
                in_string = True
            elif c == ";":
                in_comment = True
        out.append(c)
        if c == "\n":
            line_start = True
            in_comment = False
        i += 1
    return "".join(out)


def collect_it_texts(sc, start, end):
    """Return a list of (it ...) texts for the (test ...) form at [start,end).

    Well-formed input yields a single element.  Some legacy files accidentally
    nested sibling (test ...) forms inside a test's body (a missing close paren
    that FiveAM tolerated because `test` registers at macroexpansion time); such
    direct-child tests are hoisted out to become sibling `it` forms."""
    s = sc.s
    ch = sc.children(start, end)
    names, namee = ch[1]
    name = s[names:namee]
    # Locate the first direct-child nested (test ...) form, if any.
    nested_idx = None
    for idx in range(2, len(ch)):
        cs, ce = ch[idx]
        if s[cs] == "(" and sc.head_symbol(cs, ce) == "test":
            nested_idx = idx
            break
    if nested_idx is None:
        body = transform_region(sc, namee, end - 1) if len(ch) > 2 else ""
        return [f'(it "{name}"{body})']
    # This test's real body runs up to the first hoisted test.
    body = transform_region(sc, namee, ch[nested_idx][0]).rstrip()
    result = [f'(it "{name}"{body})']
    for idx in range(nested_idx, len(ch)):
        cs, ce = ch[idx]
        if s[cs] == "(" and sc.head_symbol(cs, ce) == "test":
            result.extend(collect_it_texts(sc, cs, ce))
        else:
            result.append(transform_form(sc, cs, ce))
    return result


def migrate(text, default_suite=None):
    sc = Scanner(text)
    n = len(text)
    out = []
    i = 0
    current_suite = default_suite
    # pending run of (it ...) blocks to wrap in a describe
    run = []           # list of (leading_gap, it_text)
    run_suite = None

    def flush():
        nonlocal run, run_suite
        if not run:
            return
        first_gap = run[0][0]
        inner = []
        for idx, (gap, it_text) in enumerate(run):
            inner.append(it_text if idx == 0 else gap + it_text)
        body = "".join(inner)
        wrapped = indent_block(body, "  ")
        suite = run_suite or "tests"
        # first_gap separates the describe block from the preceding form and
        # preserves any comment that sat above the first test.
        sep = first_gap if "\n" in first_gap else "\n\n" + first_gap
        out.append(sep)
        out.append(f'(describe "{suite}"\n{wrapped})')
        run = []
        run_suite = None

    while i < n:
        gap_start = i
        i = sc.skip_ws_comments(i)
        gap = text[gap_start:i]
        if i >= n:
            # trailing gap
            if run:
                # attach trailing gap after flush
                flush()
            out.append(gap)
            break
        j = sc.read_form(i)
        head = sc.head_symbol(i, j) if text[i] in "([" else None
        form_text = text[i:j]
        if head == "in-package":
            flush()
            out.append(gap)
            out.append(form_text)
        elif head == "in-suite":
            flush()
            ch = sc.children(i, j)
            if len(ch) >= 2:
                current_suite = text[ch[1][0]:ch[1][1]]
            # Drop the form.  Emit the gap only if it carries a comment, so
            # blank-line runs collapse instead of piling up.
            if gap.strip():
                out.append(gap.rstrip(" "))
        elif head == "def-suite":
            flush()
            if gap.strip():
                out.append(gap.rstrip(" "))
        elif head == "test":
            it_texts = collect_it_texts(sc, i, j)
            if run and run_suite != current_suite:
                flush()
            run_suite = current_suite
            for k, it_text in enumerate(it_texts):
                run.append((gap if k == 0 else "\n\n", it_text))
        else:
            flush()
            out.append(gap)
            out.append(transform_form(sc, i, j))
        i = j
    flush()
    return "".join(out)


if __name__ == "__main__":
    path = sys.argv[1]
    with open(path) as f:
        src = f.read()
    sys.stdout.write(migrate(src))
