rem Send the selection to the REPL -- roadmap item 23.
rem
rem The definition below is FIVE LINES, on 7 to 11. Selecting it must reach the
rem prompt as five lines -- each echoed after its own prompt, the middle three
rem after the continuation prompt -- and `twice` must then be callable.

function twice(n) local r
  r = n * 2
  println "inside twice"
  return r
endfunction

println twice(21)
