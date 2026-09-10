' tour.bas -- what the editor knows about Phosphor BASIC.
'
' Open this in PhosphorIDE and press F9. It is a smoke test as much as a demo:
' if the colours below are right and the output matches the comments, the
' highlighter, the host discovery and the output pane are all working.

rem  Both comment forms work, and both run to the end of the line.
rem  `rem` is one of only two words Phosphor's LEXER owns -- `mod` is the other --
rem  so unlike every other keyword, `rem` can never be a variable name.

' --- the five value kinds, told apart by the suffix on the name ---------------
' The suffix is PART of the name: count% and count$ are two different variables.

n = 3.14                  ' no suffix: a Double
count% = 7                ' % : Int64
name$ = "Ada"             ' $ : string
ready? = 1 < 2            ' ? : boolean
list@ = sdim@(3)          ' @ : a handle -- array, dict, file, JSON, buffer

println "n      = " + str$(n)
println "count% = " + str$(count%)
println "name$  = " + name$
println "ready? = "; ready?    ' str$ has no boolean form; PRINTLN renders it

' --- strings, and the trap that costs the most time ---------------------------
' A backslash in a literal is an ESCAPE, not a character. "C:\temp" is not a
' path: \t is a tab. The editor paints an UNKNOWN escape in red, and leaves a
' known one alone -- so the difference is visible before the compiler says so.

println "a real path needs doubling: C:\\Users\\andre"
println "or just use forward slashes: C:/Users/andre"
println "tab" + "\t" + "separated"
println "a doubled "" quote closes nothing"

' --- built-in functions, in three availability tiers -------------------------
' The editor colours these differently, because they are not equally portable.
'   core     -- always there
'   package  -- only where the host linked the package (phosphor links them all)
'   gui      -- only where a graphical session was reachable when the program ran

println ucase$(name$) + " has " + str$(len(name$)) + " characters"
println "the number 255 in hex is " + hex$(255)
println "base64: " + base64_encode$("phosphor")     ' a PACKAGE function

' --- control flow ------------------------------------------------------------
' A condition must be a COMPARISON. `if count% then` is rejected outright, and
' so is `if ready? then` -- write `if ready? = true then`.

for i = 1 to count%
  if i mod 2 = 0 then
    print "."
  else
    print str$(i)
  endif
next
println ""

' `next` takes no variable. Write `next`, never `next i`.

total% = 0
while total% < 10
  total% += 3                ' += also appends, when the left side is a string
endwhile
println "total% = " + str$(total%)

' --- arrays and dictionaries are 1-based -------------------------------------
' Everything is: array indices, string characters, string lines, instr
' positions, buffer positions. The one exception is a regex capture group.

' The bracket form is the idiomatic one: it compiles to arr_get / arr_set@, and
' the array knows its own element kind, so no typed name is needed here.
list@[1] = "first"
list@[2] = "second"
list@[3] = "third"
println "element 2 is " + list@[2]
println "the array holds " + str$(arraysize(list@)) + " " + arraytypename$(list@) + " elements"

' --- functions ---------------------------------------------------------------
' A name not listed after `local` is a GLOBAL, even inside a function. This is
' deliberate in Phosphor and is not a bug to work around.

function shout$(text$) local loud$
  loud$ = ucase$(text$) + "!"
  return loud$
endfunction

println shout$("this is phosphor")

' --- errors are values, not crashes ------------------------------------------

' A handler is a LABEL at top level. `resume next` goes back to the statement
' AFTER the one that failed -- so the flow has to jump past the handler, or it
' falls straight into it a second time.

on error goto handler
x = 1 / 0
println "resume next lands here: the statement after the one that failed"
goto finished

handler:
println "caught: " + errmsg$() + " (at line " + str$(erl()) + ")"
resume next

finished:
println "done"
