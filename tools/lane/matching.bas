rem The other end of a block -- roadmap item 22.
rem
rem Four kinds of answer live in this file: a pair that matches, a terminator
rem with nothing open above it, an opener nothing closes, and three words that
rem look like block keywords and are not.

function outer(n) local acc
  acc = 0
  for i = 1 to 3
    acc = acc + i
  next
  return acc
end function

rem a whole block on one line: the for and the next are still partners
for i = 1 to 2 println i next

rem `next` as an ordinary variable, with no for open above it. It closes
rem nothing, and the editor must say so rather than jump somewhere.
next = 5
println next

rem `function` in an expression is not at a statement position
y = function + 1
println y

rem and a block word inside a literal is not a word at all
println "for i = 1 to 3 endfunction"

rem AN OPENER NOTHING CLOSES. This while runs to the end of the file, which is
rem what makes it the unterminated case.
while y > 100
  y = y - 1
