# Contract fixtures

Every file in this directory is **broken on purpose**, except `ok.bas`.
Two of them carry no `.bas` extension on purpose: `7` is a one-character,
all-digits name, and the diagnostic it produces is the line that exposed a scan
which skipped the colon after any single-character path.
Nothing here is an example, nothing here is a demonstration of the language,
and nothing here should be copied as a starting point. They exist so that
`tests/phosphorcontract.lpr` can run the real `phosphor` binary and assert the
exact shapes `src/core/uphosphormsg.pas` claims to parse.

They are **byte fixtures**. The line numbers the host reports are asserted, so
adding or removing a line changes what the test expects; `.gitattributes`
marks them `-text` so git cannot rewrite the endings under either platform.

| file | what it is for |
| --- | --- |
| `ok.bas` | exit 0, `hello` on stdout with no terminator, stderr empty |
| `syntax.bas` | a source error found at COMPILE time |
| `divzero.bas` | a source error found at RUN time, and the packed shape |
| `nofunc.bas` | a message containing a colon, and the `--check` warning |
| `openfail.bas` | a colon before the separator and one after it, at once |
| `out_then_fail.bas` | output on stdout, the one diagnostic on stderr |
| `unhandled x.bas` | a name a refusal table would have claimed, and a real error in it |
| `7` | one character, all digits, and a colon inside its message |

Shapes with no fixture, because they need none: the packed executable (built
from `divzero.bas` at run time), the REPL (stdin, not a file), `file not
found:` (a name that deliberately does not exist), `usage:` and
`phosphor debug:` (argument shapes), and `--version` / `--help`.
