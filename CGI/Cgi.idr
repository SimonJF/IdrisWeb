module IdrisWeb.Effect.Cgi

-- CGI Module, making use of the Effects DSL. 
-- large amount of credit goes to the author of Network.Cgi.
-- SimonJF

import Effects
import CgiUtils
import CgiTypes
import SimpleParser
import Decidable.Equality
import SQLite
import Session

%access public -- for now

-- Bit of a hack for now, until I can get it so that the user doesn't
-- have to type this
initCGIState : (InitialisedCGI TaskRunning)
initCGIState = ICgi (CGIInf [] [] [] "" "" "this shouldn't happen")

showFormVal : (fty : FormTy) -> interpFormTy fty -> String
showFormVal FormString s = s
showFormVal FormInt i = show i


serialiseSubmit : String -> 
                  Vect FormTy n -> 
                  List WebEffect -> 
                  FormTy -> 
                  String
serialiseSubmit name tys effs ret = "<input type=\"hidden\" name=\"handler\" value=\"" ++ name ++ "." ++
                                     serialised_tys ++ "." ++ serialised_effs ++ "." ++ serialised_ret ++ "-\"></input>" ++
                                    "<input type=\"submit\"></input></form>"  
  where serialised_tys = foldr (\ty, str => str ++ (show ty) ++ "-") "" tys
        serialised_effs = foldr (\eff, str => str ++ (show eff) ++ "-") "" effs
        serialised_ret =  (show ret) 


val_opts : (fty : FormTy) -> (Vect (interpFormTy fty) n) -> Vect String n -> String
val_opts fty [] [] = ""
val_opts fty (val :: vals) (name :: names) = "<option value=\"" ++ (showFormVal fty val) ++ "\">" 
                                             ++ name ++ "</option>\n" ++ (val_opts fty vals names)
-- = foldr (\val, b => ("<option value=\"" ++ (showFormVal val) ++ "\">" ++ )
 
makeSelectBox : String -> (fty : FormTy) -> (Vect (interpFormTy fty) n) -> (Vect String n) -> String 
makeSelectBox name fty vals val_names = select ++ (val_opts fty vals val_names) ++ "</select><br />"
  where select = "<select name=\"" ++ name ++ "\">\n"
       
instance Handler Form m where
  handle (FR len tys ser_str) (Submit fn name effs t) k = do
    k (FR O [] ser_str) (ser_str ++ "\n" ++ (serialiseSubmit name tys effs t))
  handle (FR len tys ser_str) (AddTextBox fty val) k = do
    k (FR (S len) (fty :: tys) 
      (ser_str ++ "<input name=\"inp" ++ (show $ len)  ++ "\" value=\"" ++ (showFormVal fty val) ++ "\"></input><br />\n")) ()
  handle (FR len tys ser_str) (AddSelectionBox fty opts names) k = do
    k (FR (S len) (fty :: tys) 
      (makeSelectBox ("inp" ++ (show len)) fty opts names)) ()
    -- <input type="text" name="inpx" value="val">



{- Form handling stuff -}
-- Gets the serialised value as the given type, if it's possible
--total
parseSerialisedValue : (ty : FormTy) -> String -> Maybe (interpFormTy ty)
parseSerialisedValue FormString val = Just val
parseSerialisedValue FormInt val = case parse int val of
                                        Left err => Nothing
                                        Right (i, _) => Just i
parseSerialisedValue FormBool val = case parse bool val of
                                         Left err => Nothing
                                         Right (b, _) => Just b
-- FIXME: Placeholder for now, todo: improve parser
parseSerialisedValue FormFloat val = Just 0.0

getAs : (ty : FormTy) -> Int -> List (String, String) -> Maybe (interpFormTy ty)
getAs ty n args = do val <- lookup ("inp" ++ (show n)) args
                     parseSerialisedValue ty val

-- Disregards args
public
mkFinalHandlerType : MkHandlerFnTy -> Type
mkFinalHandlerType (_, effs, ret) = FormHandler (interpWebEffects effs) (interpFormTy ret)

getWebEnv' : (effs : List WebEffect) -> (InitialisedCGI TaskRunning) -> Effects.Env IO (interpWebEffects effs)
-- Def later


getEffects : (List FormTy, List WebEffect, FormTy) -> List EFFECT
getEffects (_, effs, _) = interpWebEffects effs

--getWebEnv : (frm_ty : MkHandlerFnTy) -> Effects.Env IO (getEffects frm_ty)
--getWebEnv (_, effs, _) = getWebEnv' effs




evalFn : (mkHTy : MkHandlerFnTy) -> 
         (counter : Int) -> -- TODO: ftys would be far better as a Vect over some finite set indexed over n
         (arg_num : Int) ->
         (args : List (String, String)) ->
         (fn : mkHandlerFn mkHTy) ->
         (InitialisedCGI TaskRunning) ->
         Maybe (mkFinalHandlerType mkHTy, PopFn)
evalFn (Prelude.List.Nil, effs, ret) counter argnum args fn cgi = Just (fn, 
       (PF effs ret (interpWebEffects effs) (getWebEnv' effs cgi) fn))-- ?mv -- Just (fn, )
evalFn ((fty :: ftys), effs, ret) counter argnum args fn cgi = let arg = getAs fty counter args in
                                                                   evalFn (ftys, effs, ret) (counter + 1) argnum args (fn arg) cgi

{- Parser functions to grab arguments from a form -}
strFty : List (String, FormTy)
strFty = [("str", FormString), ("int", FormInt), ("bool", FormBool), ("float", FormFloat)]

strEff : List (String, WebEffect)
strEff = [("cgi", CgiEffect), ("sqlite", SqliteEffect)]

arg : Parser FormTy
arg = do a_str <- strToken
         char '-'
         case lookup a_str strFty of
              Just fty => pure fty
              Nothing  => failure $ "Attempted to deserialise nonexistent function type " ++ a_str

webEff : Parser WebEffect
webEff = do e_str <- strToken
            char '-'
            case lookup e_str strEff of
                 Just w_eff => pure w_eff
                 Nothing => failure $ "Attempted to deserialise nonexistent web effect " ++ e_str

parseFormFn' : Parser (String, MkHandlerFnTy)
parseFormFn' = do name <- strToken
                  char '.'
                  args <- many arg
                  char '.' -- List delimiter
                  effs <- many webEff
                  char '.'
                  ret <- arg
                  pure (name, (args, effs, ret))
                  
-- The hidden field "handler" will be of the form:
-- <handler name>:type1;type2...typen;:<effects, eventually>:return type;
parseFormFn : String -> Maybe (String, MkHandlerFnTy)
parseFormFn str = case parse parseFormFn' str of
                       Left err => Nothing
                       Right ((name, parsed_fn), _) => Just (name, parsed_fn)

checkFunctions : (reg_fn_ty : MkHandlerFnTy) -> 
                 (frm_fn_ty : MkHandlerFnTy) -> 
                 mkHandlerFn reg_fn_ty -> 
                 Maybe (mkHandlerFn frm_fn_ty)
--checkFunctions reg_fn_ty frm_fn_ty reg_fn = if reg_fn_ty == frm_fn_ty then Just (RH frm_fn_ty reg_fn) else Nothing
checkFunctions reg_fn_ty frm_fn_ty reg_fn with (decEq reg_fn_ty frm_fn_ty)
  checkFunctions frm_fn_ty frm_fn_ty reg_fn | Yes refl = Just reg_fn
  checkFunctions reg_fn_ty frm_fn_ty reg_fn | No _ = Nothing
                                          

getReturnType : MkHandlerFnTy -> FormTy
getReturnType (_, _, ret) = ret


--getHandlerFnTy : List (String, String) -> List (String, RegHandler) -> Maybe 
-- Takes in a list of form POST / GET vars, a list of available handlers, and returns the appropriate handler
getHandler : List (String, String) -> 
             (handler_name : String) -> 
             (handler_ty : MkHandlerFnTy) -> 
             List (String, RegHandler) -> 
             (InitialisedCGI TaskRunning) -> 
             Maybe (mkFinalHandlerType handler_ty, PopFn)
getHandler vars handler_name handler_type handlers cgi = do 
                              (RH rh_type rh_fn) <- lookup handler_name handlers
                              rh_fn' <- checkFunctions rh_type handler_type rh_fn
                              let f_rh = (RH handler_type rh_fn')
                              let (tys, effs, ret) = handler_type
                              evalFn handler_type 0 0 vars rh_fn' cgi

getWebEffects : MkHandlerFnTy -> List WebEffect
getWebEffects (_, effs, _) = effs

inspectFinalEnv : (effs : List EFFECT) -> Env IO effs -> (InitialisedCGI TaskRunning) -> (InitialisedCGI TaskRunning)
inspectFinalEnv [] _ def = def
inspectFinalEnv ((CGI (InitialisedCGI TaskRunning)) :: effs) ((ICgi st) :: vals) def = (ICgi st)
inspectFinalEnv (_ :: effs) (_ :: vals) def = inspectFinalEnv effs vals def

{-
inspectCGIEnv : CGIProg effs a -> Env IO effs -> (InitialisedCGI TaskRunning) -> (InitialisedCGI TaskRunning)
inspectCGIEnv fn [] def = def
inspectCGIEnv fn ((ICgi st) :: xs) _ = (ICgi st)
inspectCGIEnv fn (_ :: xs) def = inspectCGIEnv fn xs def
-}

--Eff IO 
addOutput : String -> CGIInfo -> CGIInfo
-- TODO: GetEnv on the CGI
executeHandler : List (String, String) -> List (String, RegHandler) -> (InitialisedCGI TaskRunning) -> IO (InitialisedCGI TaskRunning, Bool)
executeHandler vars handlers cgi = case (lookup "handler" vars) >>= parseFormFn of
                                      Just (name, frm_ty) => case getHandler vars name frm_ty handlers cgi of
                                        Just (fn, (PF effs ret conc_effs env fn')) => do (env', res) <- runEnv env fn'
                                                                                         let cgi' = inspectFinalEnv conc_effs env' cgi
                                                                                         pure (cgi', True)
                                        Nothing => do let (ICgi st) = cgi
                                                      let cgi' = (addOutput "Found handler field; could not execute" st)
                                                      pure ((ICgi cgi'), False)
                                      Nothing => do let (ICgi st) = cgi
                                                    let cgi' = (addOutput "Could not find handler in vars / could not parse" st)
                                                    pure ((ICgi cgi'), False)






-- TODO: Action, also ideally we should have encoding/decoding instead of using text/plain
mkForm : String -> String -> UserForm -> SerialisedForm
mkForm name action frm = runPure [FR O [] ("<form name=\"" ++ name ++ 
                         "\" action=\"" ++ action ++ "\" method=\"post\">\n")] frm


-- In handle, then match on (ICGI s) to get access to state
-- State mutation functions, allowing for addition of headers / output
addHeaders : String -> CGIInfo -> CGIInfo
addHeaders str st = record { Headers = Headers st ++ str ++ "\r\n" } st

--addOutput : String -> CGIInfo -> CGIInfo
addOutput str st = record { Output = Output st ++ str } st


-- To create a CGI Program in Network.Cgi, one imports Network.Cgi,
-- and then creates a function CGIInfo -> IO (a, CGIInfo)) which is passed
-- into MkCGI.

-- This produces a complete CGI program, which can then be executed with
-- the required arguments.


-- For the implementation of CGI in the effects language, we'll want users
-- to be able to specify some function to be run inside the CGI effect.

-- This will take the form Eff IO [CGI] a, or more simply
-- CGIEff a.

-- Several CGI functions will also require access to the state, and some will require
-- access to the environment variables.


abstract
runAction : Env IO (CGI (InitialisedCGI TaskRunning) :: effs) -> CGIProg effs a -> Eff m [CGI (InitialisedCGI TaskRunning)] a
runAction init_env act = (RunAction init_env act)

getInfo : Eff m [CGI (InitialisedCGI TaskRunning)] CGIInfo
getInfo = GetInfo

abstract
getGETVars : Eff m [CGI (InitialisedCGI TaskRunning)] Vars
getGETVars = GETVars

abstract
getPOSTVars : Eff m [CGI (InitialisedCGI TaskRunning)] Vars
getPOSTVars = POSTVars

abstract
getCookieVars : Eff m [CGI (InitialisedCGI TaskRunning)] Vars
getCookieVars = CookieVars

abstract
queryGetVar : String -> Eff m [CGI (InitialisedCGI TaskRunning)] (Maybe String)
queryGetVar query = (QueryGetVar query)

abstract
queryCookieVar : String -> Eff m [CGI (InitialisedCGI TaskRunning)] (Maybe String)
queryCookieVar query = (QueryCookieVar query)

abstract
queryPostVar : String -> Eff m [CGI (InitialisedCGI TaskRunning)] (Maybe String)
queryPostVar query = (QueryPostVar query)

getOutput : Eff m [CGI (InitialisedCGI TaskRunning)] String
getOutput = GetOutput

getHeaders : Eff m [CGI (InitialisedCGI TaskRunning)] String
getHeaders = GetHeaders

abstract
flushHeaders : Eff m [CGI (InitialisedCGI TaskRunning)] ()
flushHeaders = FlushHeaders

abstract
flush : Eff m [CGI (InitialisedCGI TaskRunning)] ()
flush = Flush

initialise : EffM m [CGI ()] [CGI (InitialisedCGI Initialised)] ()
initialise = Init

startTask : EffM m [CGI (InitialisedCGI Initialised)] [CGI (InitialisedCGI TaskRunning)] ()
startTask = StartRun

finishTask : EffM m [CGI (InitialisedCGI TaskRunning)] [CGI (InitialisedCGI TaskCompleted)] ()
finishTask = FinishRun

writeHeaders : EffM m [CGI (InitialisedCGI TaskCompleted)] [CGI (InitialisedCGI HeadersWritten)] ()
writeHeaders = WriteHeaders

writeContent : EffM m [CGI (InitialisedCGI HeadersWritten)] [CGI (InitialisedCGI ContentWritten)] ()
writeContent = WriteContent

abstract
setCookie : String -> String -> Eff m [CGI (InitialisedCGI TaskRunning)] ()
setCookie name val = (SetCookie name val)

public
output : String -> Eff m [CGI (InitialisedCGI TaskRunning)] ()
output s = (OutputData s)

abstract
addForm : String -> String -> UserForm -> Eff m [CGI (InitialisedCGI TaskRunning)] ()
addForm name action form = (AddForm name action form)

abstract
handleForm : List (String, RegHandler) -> Eff m [CGI (InitialisedCGI TaskRunning)] Bool
handleForm handlers = (HandleForm handlers)

-- Handler for CGI in the IO context
instance Handler Cgi IO where
  --handle (ICgi st) GetInfo k = k (ICgi st) (CgiInfo st)

  handle (ICgi st) GETVars k = k (ICgi st) (GET st)

  handle (ICgi st) POSTVars k = k (ICgi st) (POST st)

  handle (ICgi st) CookieVars k = k (ICgi st) (Cookies st)

  handle (ICgi st) (QueryGetVar q) k = k (ICgi st) (lookup q (GET st))

  handle (ICgi st) (QueryPostVar q) k = k (ICgi st) (lookup q (POST st))

  handle (ICgi st) (QueryCookieVar q) k = k (ICgi st) (lookup q (Cookies st))

  handle (ICgi st) GetOutput k = k (ICgi st) (Output st)

  handle (ICgi st) GetHeaders k = k (ICgi st) (Headers st)

  -- Should this also clear them from the state? It doesn't in the Network.Cgi imp
  -- but seems logical
  handle (ICgi st) FlushHeaders k = do putStrLn (Headers st)
                                       k (ICgi st) ()

  -- These two are purely to transition states, so we don't need to do anything
  handle (ICgi st) StartRun k = k (ICgi st) ()
  handle (ICgi st) FinishRun k = k (ICgi st) ()

  -- Handle writing out headers and content
  handle (ICgi st) WriteHeaders k = do putStr (Headers st)
                                       putStr "\r\n"
                                       k (ICgi st) ()
                                       
  -- Handle writing out headers and content
  handle (ICgi st) WriteContent  k = do --putStrLn ("OC: " ++ s)
                                         putStrLn (Output st)
                                         k (ICgi st) ()

  handle (ICgi st) Flush k = do putStrLn (Output st)
                                k (ICgi st) ()

  -- Get the variables from the environment
  handle () Init k = do 
    query   <- safeGetEnvVar "QUERY_STRING"
    cookie  <- safeGetEnvVar "HTTP_COOKIE"
    agent   <- safeGetEnvVar "HTTP_USER_AGENT"
    content <- getContent
    let get_vars  = getVars ['&',';'] query
    let post_vars = getVars ['&'] content -- TODO: plain/text encoding
    let cookies   = getVars [';'] cookie
            
    let cgi_info = (CGIInf get_vars post_vars cookies agent
                    "Content-type: text/html\n" "")
    k (ICgi cgi_info) ()

  handle (ICgi st) (OutputData s) k  = do let new_cgi_info = addOutput s st
                                          k (ICgi new_cgi_info) ()

-- TODO: don't hardcode date :P #lazyintern
  handle (ICgi st) (SetCookie name val) k = do let set_cookie_header = ("Set-Cookie: " ++ 
                                                name ++ "=" ++ val ++ 
                                                "; Expires=Thu, 26 Jun 2014 10:00:00 GMT")
                                               let new_info = addHeaders set_cookie_header st
                                               k (ICgi new_info) ()

  handle (ICgi st) (RunAction ((ICgi _) :: env) act) k = do (((ICgi st') :: env'), result) <- runEnv ((ICgi st) :: env) act 
                                                            k (ICgi st') result

  handle (ICgi st) (AddForm name action form) k = k (ICgi $ addOutput (mkForm name action form) st) ()

  -- TODO: allow GET vars
  handle (ICgi st) (HandleForm handlers) k = do let post_vars = POST st
                                                (cgi', res) <- executeHandler post_vars handlers (ICgi st)
                                                -- *really* need to update CGI state, and allow return vals
                                                k cgi' res

-- Internal mechanism to run the user-specified action
private
runCGI' : Env IO ((CGI (InitialisedCGI TaskRunning)) :: effs) -> 
          CGIProg effs a -> 
          EffM IO [CGI ()] [CGI (InitialisedCGI ContentWritten)] a
runCGI' init_effs action = do initialise 
                              -- Transition to TaskRunning
                              startTask
                              -- Perform the user-defined action and collect the result
                              res <- runAction init_effs action
                              -- Transition to TaskComplete
                              finishTask
                              -- Write out the headers
                              writeHeaders
                              -- Write out the content
                              writeContent
                              -- Finally, return the result
                              pure res 

public
runCGI : Env IO ((CGI (InitialisedCGI TaskRunning)) :: effs) -> CGIProg effs a -> IO a
runCGI init_env act = do result <- run [()] (runCGI' init_env act)
                         pure result


getWebEnv' [] _ = []
getWebEnv' (CgiEffect :: xs) cgi = (cgi) :: getWebEnv' xs cgi
getWebEnv' (SqliteEffect :: xs) cgi = (()) :: getWebEnv' xs cgi


