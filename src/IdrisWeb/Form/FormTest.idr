module Main
--module IdrisWeb.Form.FormTest
import Cgi
import Effects
--import Debug.Trace

total
outputCommaList : List String -> String
outputCommaList [] = ""
outputCommaList [x] = x ++ "."
outputCommaList (x :: y :: []) = x ++ " and " ++ y ++ "."
outputCommaList (x :: xs) = x ++ ", " ++ outputCommaList xs

sampleHandler : Maybe String -> 
                Maybe Int -> 
                FormHandler [CGI (InitialisedCGI TaskRunning), SQLITE ()]
sampleHandler (Just name) (Just age) = do (output ("Your name is: " ++ name ++ 
                                            ", and you are " ++ (show age) ++ " years old!"))
                                          pure ()
sampleHandler _ _ = do output "There was an error processing form data."
                       pure ()

sampleHandler2 : Maybe String -> 
                Maybe Int -> 
                FormHandler [CGI (InitialisedCGI TaskRunning), SQLITE ()]
sampleHandler2 (Just name) (Just age) = do (output ("Your name is: " ++ name ++ 
                                             ", and you are " ++ (show age) ++ " years old!"))
                                           pure ()
sampleHandler2 _ _ = do output "There was an error processing form data."
                        pure ()

-- Some syntax macro magic might be nice here
handlers : HandlerList
handlers = [(([FormString, FormInt], [CgiEffect, SqliteEffect]) ** (sampleHandler, "sampleHandler")),
            (([FormString, FormInt], [CgiEffect, SqliteEffect]) ** (sampleHandler2, "sampleHandler2"))]

sampleForm : UserForm --UserForm
sampleForm = do addTextBox "Name: " FormString (Just "Simon")
                addTextBox "Age: " FormInt Nothing-- 21
                useEffects [CgiEffect, SqliteEffect]
                addSubmit sampleHandler handlers 


cgiAction : CGIProg [] ()
cgiAction = do output "<h1>Simon's awesome sauce form stuff!</h1>\n"
               handlervar <- queryPostVar "handler"
               post_vars <- getPOSTVars
               let post_vars_str = foldr (\(k, v), str => str ++ k ++ " :-> " ++ v ++ "<br />") "" post_vars
               output "Post vars: <br />"
               output post_vars_str
               --sequence (map (\(name, val) => output $ "Name: " ++ name ++ ", " ++ val ++ "<br />") post_vars)
               case handlervar of
                    -- If at all poss, this needs to be cleaner. Users shouldn't have to type this
                    Just _ => do res <- handleForm handlers
                                 pure ()
                    Nothing => do addForm "sampleForm" "formtest" sampleForm 
                                  pure ()
main : IO ()
main = do runCGI [initCGIState] cgiAction
          pure ()
