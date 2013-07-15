module Main
import Effects
import SQLite
import CgiTypes

-- We could also have SQLITE, or CGI here perhaps
sampleHandler : Maybe String -> Maybe Int -> Maybe Int -> FormHandler [CGI (InitialisedCGI TaskRunning)] Bool 
sampleHandler (Just name) (Just age) (Just num) = ((output ("Your name is " ++ name 
              ++ " and you are " ++ (show age) ++ " years old. You selected: " ++ (show num))) >>= (\_ pure True))
sampleHandler _ _ _ = output "There was an error processing input data." >>= (\_ => pure False)


-- Effects.>>= : (EffM m xs xs' a) -> (a -> EffM m xs' xs'' b) -> EffM xs xs'' b
-- addTextBox str >>= addTextBox int : EffM m [] [FormString] () -> EffM m [FormString] [FormInt, FormString] () -> EffM m [] [FormInt, FormString]
myForm : UserForm
myForm = do addTextBox FormString "Simon"
            addTextBox FormInt 21
            addSelectionBox FormInt [1,2,3,4] ["One", "Two", "Three", "Four"]
            addSubmit sampleHandler [CgiEffect] FormBool
  --(addTextBox FormString "Simon") >>= ((\_ => addTextBox FormInt 21) >>= (\_ => addSubmit sampleHandler))




main : IO ()
main = do let ser_form = mkForm "myform" myForm
          putStrLn ser_form

