' AMAZING -- a random maze and its one path through (after Creative Computing's
' AMAZING): the size from the command line (AMAZING 13 10) or INPUT, ON GOTO,
' labels, FUNCTIONs and SUBs
  Print "THIS PROGRAM WILL PRINT A DIFFERENT MAZE EACH TIME IT IS"
  Print "RUN.  THERE WILL BE A UNIQUE PATH THROUGH THE MAZE.  YOU"
  Print "CAN CHOOSE ANY DIMENSIONS FOR THE MAZE UP TO 49 SQUARES"
  Print "LONG AND 49 SQUARES WIDE."
  Print

  dim shared R9, C9, F, C0, R0
  ' the length and width from the command line (AMAZING 13 10, or 13,10);
  ' without them (or out of range), asked for
  dim cmd$, k
  cmd$ = COMMAND$
  for k = 1 to len(cmd$)
     if mid$(cmd$, k, 1) = "," then cmd$ = left$(cmd$, k - 1) + " " + mid$(cmd$, k + 1)
  next k
  cmd$ = ltrim$(rtrim$(cmd$))
  k = instr(cmd$, " ")
  if k > 0 then
     R9 = val(left$(cmd$, k - 1))
     C9 = val(ltrim$(mid$(cmd$, k + 1)))
  end if
  do while R9 < 1 or C9 < 1 or R9 > 49 or C9 > 49
     Print "WHAT ARE YOUR LENGTH AND WIDTH (E. G. 13,10)";
     Input R9, C9
  loop
  randomize timer

  Dim shared W(50,50) as integer, V(50,50) as byte
  dim shared S(50,50) as byte
  Dim Direction(4) as byte
  Const LEFT=1, RIGHT=2, UP=3, DOWN=4
  N9 = R9*C9

 B = 0                           'FLAG NO EXIT TO BOTTOM YET
 '     FIND SQUARE IN WHICH TO START
 F = Int(Rnd*C9+1)
 Print                           'PRINT TOP BORDER
 R = 1                           'START IN FIRST ROW
 C = F                           'AND COLUMN UNDER HOLE IN BORDER
 N = 1                           'COUNT OF SQUARES VISITED
 W(R,C) = N

 '  A CORRIDOR IS CONSTRUCTED BY MOVING IN A RANDOM DIRECTION FROM
 '  THE CURRENT SQUARE TO SOME SQUARE THAT HAS NOT BEEN VISITED
 '  YET AND ERASING THE WALL BETWEEN THE TWO SQUARES.  IF NO SUCH
 '  MOVE IS POSSIBLE, A SIDE CORRIDOR IS STARTED IN SOME SQUARE
 '  ALREADY VISITED WHICH IS ADJACENT TO AN UNVISITED SQUARE.  ONLY
 '  ONE EXIT TO THE BOTTOM OF THE MAZE IS ALLOWED.
 '
 '                  MAKE LIST OF UNBLOCKED DIRECTIONS

Make_List_of_Unblocked_Dir:
    D = 0

'                   CAN WE GO LEFT
    If C <> 1 Then                       'NO, ON BORDER
       If W(R,C-1) <= 0 Then             'NO, SQUARE USED ALREADY
          D = D+1                        'YES, ADD "LEFT" TO LIST
          Direction(D) = 1
       end if
    end if

 '                  CAN WE GO RIGHT
    If C <> C9 Then                       'NO, ON BORDER
       If W(R,C+1) <= 0 Then              'NO, SQUARE USED ALREADY
          D = D+1                         'YES, ADD "RIGHT" TO LIST
          Direction(D) = 2
       end if
    end if

 '                  CAN WE GO UP
    If R > 1 Then                         'NO, ON BORDER
       If W(R-1,C) <= 0 Then              'NO, SQUARE USED ALREADY
          D = D+1                         'YES, ADD "UP" TO LIST
          Direction(D) = 3
       end if
    end if

'                   CAN WE GO DOWN
If R < R9 Then                           'MAYBE, NOT ON BORDER
   If W(R+1,C) <= 0 Then                 'NO, SQUARE USED ALREADY
      D = D+1                            'YES, ADD "DOWN" TO LIST
      Direction(D) = 4
   end if
else
   If B <> 1 Then                     'NO, ALREADY HAVE EXIT TO BOTTOM
      D = D+1                         'YES, ADD "DOWN" TO LIST
      Direction(D) = 4
   end if
end if


'                CHOOSE DIRECTION
If D = 0 goto restart            'ALL DIRECTIONS BLOCKED
X = Int(D*Rnd+1)                      'PICK RANDOM DIRECTION

On Direction(X) GoTo go_left, go_right, go_up, go_down

go_left:
           C = C-1
           V(R,C) = 2                      'NEW SQUARE HAS ONLY BOTTOM WALL
           GoTo mark_square

go_right:
           V(R,C) = V(R,C) + 2             'ERASE RIGHT WALL OF THIS SQUARE
           C = C+1
           GoTo mark_square

go_up:
           R = R-1
           V(R,C) = 1                      'NEW SQUARE HAS ONLY RIGHT WALL
           GoTo mark_square

go_down:
           V(R,C) = V(R,C) + 1             'ERASE BOTTOM WALL OF THIS SQUARE
           R = R+1
           If R > R9 Then                  'not STILL IN MAZE
              B = 1                        'FLAG EXIT TO BOTTOM
              C0 = C
              R0 = R-1

              R = 1
              C = 1
              goTo chk_if_restart          'AND GO VISIT OTHER SQUARES
           end if

mark_square:
           N = N+1                         'MARK SQUARE AS USED
           W(R,C) = N
           if N < N9 goto Make_List_of_Unblocked_Dir
           GoTo prt_maze                   ' DONE!

restart:
'               RESTART IN USED SQUARE ADJACENT TO UNUSED SQUARE
C = C+1
If C > C9 Then
    C = 1
    R = R+1
    If R > R9 Then R = 1
end if

chk_if_restart:

If W(R,C) > 0 goto Make_List_of_Unblocked_Dir
GoTo restart

'
'
'        *******************   PRINT OUT MAZE   ********************
'
'
function print_3_digits$( n )
    dim num$
    num$ = str$( n )
    num$ = left$(num$+"       ", 4)
    print_3_digits$ = num$
end function

prt_maze:
     If B <> 1 Then                   'NO EXIT TO BOTTOM YET: MAKE ONE
        C0 = Int(Rnd*C9+1)
        R0 = R9
        V(R0,C0) = V(R0,C0) + 1
        B = 1
     end if
     Print                            'PRINT TOP BORDER
     For C = 1 To C9
        If C = F Then  Print ":   "; Else  Print ":---";
     Next C
     Print ":"

     For R = 1 To R9
        Print "|";
        For C = 1 To C9
            If V(R,C) < 2 Then
               Print "   |";
            else
               Print "    ";
            end if
        Next C

        print "   ";
        for c = 1 to c9
           print print_3_digits$( w(r,c) );
        next c

        Print
        For C = 1 To C9
           If (v(r,c) mod 2) = 0 Then
               Print ":---";
           else
               Print ":   ";
           end if
        Next C
        Print ":"
     Next R
     Print
     Print

     print_solution


Function Can_Go_To(dir%, x%, y%) As INTEGER
 If dir%=LEFT Then
   If x%<2 then
      Can_Go_To = 0
      exit function
   end if
   If v(y%,x%-1) >=2 Then Can_Go_To=1 Else Can_Go_To=0
   Exit Function
 end if

 If dir%=RIGHT Then
    If x%>=c9 then
       Can_Go_To = 0
       exit function
    end if
    If v(y%,x%) >=2 Then Can_Go_To=1 Else Can_Go_To=0
    Exit Function
 end if

 If dir%=UP then
    If y%<2 then
       Can_Go_To = 0
       exit function
    end if
    If v(y%-1,x%)=1 Or  v(y%-1,x%)=3 Then Can_Go_To=1 Else Can_Go_To=0
    exit Function
 end if

 If dir%<>DOWN Then
      Print "Illegal direction in function Can_Go_To(";dir%;")"
      end
 end if

 If y%<r9 then
      If v(y%,x%)=1 Or  v(y%,x%)=3 Then Can_Go_To=1 Else Can_Go_To=0
             exit Function
 end if

End Function

sub print_wall_data
        dim i as integer, j as integer

        for i = 1 to c9
                if i <> f then print ":---"; else print ":   ";
        next i
        print

        for j = 1 to r9
                print "| ";
                for i = 1 to c9
                        print  right$( str$(v(j,i)),1); " ";
                        if (v(j,i) and &h02)=0 then print "| "; else print "  ";
                next i
                print

                for i = 1 to c9
                        if (v(j,i) and &h01)=0 then print ":___"; else print ":   ";
                next i
                print ":"
        next j
        print
end sub

sub map_solution
dim i, j, lowest as integer, cnt as integer, dir as integer
dim bi as integer, bj as integer

        i = c0
        j = r0
loopy:
'        print "(";i;",";j;") ";
        cnt = cnt+1
        if cnt > 10 then
            cnt = 0
            print
        end if

        s(j,i) = 1
        if can_go_to( LEFT, i, j) and w(j,i-1) = w(j,i)-1  then
                i = i-1
                goto loopy
        end if

        if can_go_to( RIGHT, i, j) and w(j,i+1) = w(j,i)-1  then
                i = i+1
                goto loopy
        end if

        if can_go_to( UP, i, j) and w(j-1,i) = w(j,i)-1  then
                j = j-1
                goto loopy
        end if

        if can_go_to( DOWN, i, j) and w(j+1,i) = w(j,i)-1  then
                j = j+1
                goto loopy
        end if

'        print "Broken path at ("; j; ","; i;") Sq="; w(j,i)
        if w(j,i)=1 then  exit function

        lowest = w(j,i)
        if can_go_to( LEFT, i, j) then
                if  w(j,i-1) < lowest  then
                        lowest = w(j,i-1)
                        dir = LEFT
                        bi = i-1
                        bj = j
                end if
        end if

        if can_go_to( RIGHT, i, j)  then
                if  w(j,i+1) < lowest  then
                        lowest = w(j,i+1)
                        dir = RIGHT
                        bi = i+1
                        bj = j
                end if
        end if

        if can_go_to( UP, i, j)  then
                if  w(j-1,i) < lowest  then
                        lowest = w(j-1,i)
                        dir = UP
                        bi = i
                        bj = j-1
                end if
        end if

        if can_go_to( DOWN, i, j)  then
                if  w(j+1,i) < lowest  then
                        lowest = w(j+1,i)
                        dir = DOWN
                        bi = i
                        bj = j+1
                end if
        end if

        i = bi
        j = bj
        s(j,i) = 1

        if w(j,i) <> 1 then goto loopy
'       current_solution
end sub

Sub current_solution
     For C7 = 1 To C9
        If c7<10 Then Print C7; Else print right$( str$(c7),3);
     Next C7
     Print                            'PRINT TOP BORDER of solution
     For C7 = 1 To C9
       If C7 = F Then  Print "+  "; Else  Print "+--";
     Next C7
     '
     Print "|"
     '
     For R7= 1 To R9
        Print "|";
        For C7 = 1 To C9
           If V(R7,C7) < 2 Goto lab0
           If s(r7,c7)=0 Then Print "   "; Else Print " # ";
           GoTo lab1
lab0:      If s(r7,c7)=0 Then Print "  |"; Else Print " #|";
lab1:   Next C7
        Print r7
        For C7 = 1 To C9
           If (v(r7,c7) Mod 2) = 0 Goto lab2
           Print "+  ";
           GoTo lab3
lab2:      Print "+--";
lab3:   Next C7
        Print "|"
     Next R7
End Sub

sub print_solution
'    print "Wall map: "
'    print_wall_data
'    print "========================================================================"
     map_solution
     current_solution
end sub


end


