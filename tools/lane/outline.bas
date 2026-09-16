rem Ten definitions, and FIVE of them sit where a first-word scanner will not
rem look: second, third, fourth$, and both fifth% and sixth% on one line.
rem This one is a comment, and it defines nothing: rem function ghost()
' function alsoghost()
println "function stringghost()"

function first()
  return 1
endfunction

x = 1 : function second(a, b)
  return a + b
end function

if x > 0 then function third()
  return 3
endfunction

10 function fourth$()
  return "4"
endfunction

head: function fifth%() return 5 : end function : function sixth%() return 6 : end function

FUNCTION Seventh()
  RETURN 7
END FUNCTION

function eighth?(n)
  return n > 0
endfunction

function ninth@()
  return null
endfunction

function tenth(a)
  return a * 2
endfunction

println first()
println second(2, 3)
println third()
println fourth$()
println fifth%()
println sixth%()
println Seventh()
println eighth?(1)
println tenth(21)
println abs(-3)
