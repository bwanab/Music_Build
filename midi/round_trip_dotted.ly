\version "2.24.4" 

    \book
    {
      \header
        {
          title = "No Name"
        }
      \score
        {
        <<
          
    \new Staff
    {
      \time 4/4
      \tempo 4 = 90
      \new Voice
      {
         c'4 r4 < a' cis'' e'' >4 e'4 f'4 g'4. ges'2.
      }
    }
    
        >>
        \layout {
              \context {
              \Voice
              \remove Note_heads_engraver
              \consists Completion_heads_engraver
              \remove Rest_engraver
              \consists Completion_rest_engraver
           }

        }
        \midi { }
      }
    }