module Environment where

import qualified Data.Map as M
import           Text.Parsec.Pos
import           Control.Applicative
import           Control.Monad
import           Control.Monad.Writer
import           Control.Monad.State.Strict

import AST
import AnalyzedAST
import ErrorMsg

type StateEnv = StateT Env (Writer [String])

runEnv :: StateEnv a -> Env -> (a, [String])
runEnv s env = runWriter (evalStateT s env)

type Env   = M.Map Level [(Identifier, ObjInfo)]


global_lev :: Level
global_lev = 0

param_lev :: Level
param_lev = 1

func_lev :: Level
func_lev = 2

-- グローバルな宣言だけを集める
collectGDecl :: Program -> StateEnv ()
collectGDecl = mapM_ collectEdecl

collectEdecl :: EDecl -> StateEnv ()
collectEdecl (Decl p l) = mapM_ (addEnv global_lev) (map (makeVarInfo p global_lev) l)
collectEdecl (FuncPrototype p ty nm args)
    = do {
        let { funcInfo = makeFuncInfo ty args FuncProto } ;
        info <- findAtTheLevel global_lev nm;
        case info of
          (Just i) -> if i == funcInfo
                      then return ()
                      else protoTypeError p nm
          Nothing  -> addEnv global_lev (nm, funcInfo); }
collectEdecl (FuncDef p dcl_ty name args stmt)
    = do {
        let { funcInfo = makeFuncInfo dcl_ty args Func; };
        maybeInfo <- findAtTheLevel global_lev name;
        case maybeInfo of
          (Just info) -> case info of
                           (ObjInfo FuncProto ty _)
                               -> if ty == ctype funcInfo
                                  then addEnv global_lev (name, funcInfo)
                                  else funcDeclError p name
                           (ObjInfo Func _ _) -> funcDeclError p name
                           _                  -> addEnv global_lev (name, funcInfo)
          Nothing  -> addEnv global_lev (name, funcInfo); }

makeFuncInfo :: DeclType -> [(DeclType, Identifier)] -> Kind -> ObjInfo
makeFuncInfo ty args kind = ObjInfo kind (CFun retTy argsTy) global_lev
    where retTy  = convType ty
          argsTy = map (convType . fst) args

makeVarInfo :: SourcePos -> Level -> (DeclType, DirectDecl) -> (Identifier, ObjInfo)
makeVarInfo p lev (dcl_ty, dcl)
    = let ty = convType dcl_ty in
      if containVoid ty
      then voidError p
      else case dcl of
             (Variable _ name)      -> (name, ObjInfo Var ty lev)
             (Sequence _ name size) -> (name, ObjInfo Var (CArray ty size) lev)

makeParmInfo :: SourcePos -> (DeclType, Identifier) -> (Identifier, ObjInfo)
makeParmInfo p (dcl_ty, name)
    = let ty = convType dcl_ty in
      if containVoid ty
      then voidError p
      else (name, ObjInfo Parm ty param_lev)

convType :: DeclType -> CType
convType (DeclPointer ty) = CPointer (convType ty)
convType (DeclInt)        = CInt
convType (DeclVoid)       = CVoid

addEnv :: Level -> (Identifier, ObjInfo) -> StateEnv ()
addEnv lev info_entry = liftM (M.insertWith (++) lev [info_entry]) get >>= put

extendEnv :: SourcePos -> Level -> (Identifier, ObjInfo) -> StateEnv ()
extendEnv p lev (name, info)
    = do {
        dupInfo <- findAtTheLevel lev name;
        case dupInfo of
          Nothing  -> tellShadowing p name lev >> addEnv lev (name, info)
          (Just _) -> duplicateError p name; }

tellShadowing :: SourcePos -> Identifier -> Level -> StateEnv ()
tellShadowing p name baseLev
    = do {
        hiddenInfo <- find (baseLev-1) name;
        case hiddenInfo of
          (Just _) -> tell $ [warningMsg p name]
          Nothing  -> return (); }

deleteLevel :: Level -> StateEnv ()
deleteLevel lev = (liftM (M.delete lev) get) >>= put

withEnv :: Level -> StateEnv () -> StateEnv a -> StateEnv a
withEnv lev mkenv body = mkenv >> body <* deleteLevel lev

find :: Level -> Identifier -> StateEnv (Maybe ObjInfo)
find lev name = if lev <= -1 then return Nothing
                else do {
                       env <- get;
                       case (M.lookup lev env >>= lookup name) of
                         (Just info) -> return $ Just info
                         Nothing     -> find (lev-1) name; }

findFromJust :: SourcePos -> Level -> Identifier -> StateEnv ObjInfo
findFromJust p lev name
    = do {
        maybeInfo <- find lev name;
        case maybeInfo of
          (Just info) -> return info
          Nothing     -> undefinedError p name; }

findAtTheLevel :: Level -> Identifier -> StateEnv (Maybe ObjInfo)
findAtTheLevel lev name = liftM (\e -> M.lookup lev e >>= lookup name) get

containVoid :: CType -> Bool
containVoid (CVoid)       = True
containVoid (CArray ty _) = containVoid ty
containVoid (CPointer ty) = containVoid ty
containVoid _             = False
