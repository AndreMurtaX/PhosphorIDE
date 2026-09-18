rem The program that found the missing affordance.
rem
rem On 2026-09-17 the author of this editor ran ../Phosphor/tests/classic/04_input.bas
rem in it, watched `Name? ` arrive in the Output pane, did not connect that prompt
rem to the edit box below the transcript, and killed the process rather than answer
rem it. This is the same shape, cut down to the one exchange that matters.
rem
rem `input "Name"; who$` prints its prompt WITHOUT a newline, so it reaches the
rem editor as an unterminated tail and is flushed after two idle drain ticks --
rem which is the case uphosphorrun treats as a prompt. That is the moment the
rem hint on EditInput has to be readable.
input "Name"; who$
println "hello, "; who$
