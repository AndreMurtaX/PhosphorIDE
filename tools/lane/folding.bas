rem Folding, and the lines that only look like blocks.
rem The four at the bottom must show NO fold marker in the gutter: each of them
rem is legal Phosphor that an obvious folder would fold, and each would then
rem hide everything below it.

function outer(n) local acc
  acc = 0
  for i = 1 to 3
    if n > 0 then
      acc = acc + i
    endif
  next
  while acc > 10
    acc = acc - 1
  wend
  return acc
end function

rem a whole block on one line -- opens and closes here, so it folds nothing
for i = 1 to 2 println i next

rem an inline if -- `then` is not the last thing on the line, so no block
if 1 = 1 then println 7

rem `function` as an ordinary variable. Not at the start of a statement: there
rem it is always a definition, and `function = 5` is `expected a function name`.
y = function + 1
println y

rem and a block word inside a literal
println "for i = 1 to 3 endfunction"

println outer(1)
