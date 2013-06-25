module IdrisWeb.Effect.Cgi

-- Pure functions used by the CGI effects library
-- SimonJF

import System


-- Simple type synonym for a list of key value pairs
public
Vars : Type
Vars = List (String, String)

 
-- Pure, non-effecting functions
abstract
getVars : List Char -> String -> List (String, String)
getVars seps query = mapMaybe readVar (split (\x => elem x seps) query)
  where
        readVar : String -> Maybe (String, String)
        readVar xs with (split (\x => x == '=') xs)
                | [k, v] = Just (trim k, trim v)
                | _      = Nothing

-- Credits: pxqr
abstract
getEnv' : String -> IO (Maybe String)
getEnv' x = do
      ptr <- mkForeign (FFun "getenv" [FString] FPtr) x
      n   <- nullPtr ptr
      if n then pure Nothing
      -- maybe there is a way to marshal the 'ptr' to a string?
           else fmap Just (getEnv x)

-- Returns either the environment variable, or the empty string if it does not exist
abstract
safeGetEnvVar : String -> IO String
safeGetEnvVar varname = do env_var <- getEnv' varname
                           case env_var of
                                Just var => pure var
                                Nothing =>  pure ""


private
getContent' : Int -> IO String --Eff IO [EXTENDEDSTDIO] String
getContent' x = getC x "" where
      %assert_total
      getC : Int -> String -> IO String
      getC 0 acc = pure $ reverse acc
      getC n acc = if (n > 0)
                      then do x <- getChar
                              getC (n-1) (strCons x acc)
                      else (pure "")



-- Gets the content of the user data.
-- If CONTENT_LENGTH is not present, returns the empty string.
abstract
getContent : IO String
getContent = do
    clen_in <- getEnv' "CONTENT_LENGTH" -- Check for CONTENT_LENGTH existence
    case clen_in of
         Just content_length => do let clen = prim__fromStrInt content_length
                                   getContent' clen -- Get content from content length
         Nothing             => pure ""



