rem 1 a comment: nothing can stop here
total = 0

function add(a, b) local s
  s = a + b
  return s
endfunction

println "start"
total = add(2, 3)
println "after first add, total = " + str$(total)
total = add(total, 10)
println "after second add, total = " + str$(total)
println "done"
