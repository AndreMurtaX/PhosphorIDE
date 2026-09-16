rem three levels of recursion, so a call-stack pane has something to show
function down(n) local r
  if n <= 0 then
    println "bottom"
    return 0
  endif
  r = down(n - 1)
  return r + n
endfunction

total = down(3)
println "total = " + str$(total)
