rem A diagnostic you can see in the text -- roadmap item 24.
println "before"
rem LINE 4 IS THE ERROR: `println 1 +` has nothing after the operator, and the
println 1 +
rem host answers `phosphor: blame.bas:4: unexpected token in expression`.
println "after"
