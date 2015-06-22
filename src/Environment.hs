module Environment where

import qualified Data.Map as M
import           Text.Parsec.Pos
import           Control.Applicative
import           Control.Monad
import           Control.Monad.State.Strict
import Debug.Trace
import AST

type StateEnv = State Env

type Env   = M.Map Level [Info]
type Level = Int
type Info  = (Identifier, (Kind, CType))
data Kind  = Var | Func | FuncProto | Parm deriving(Show, Eq, Ord)
data CType = CInt
           | CVoid
           | CNone
           | CPointer CType
           | CArray   CType Integer
           | CFun     CType [CType]
           deriving(Show, Eq, Ord)


-- グローバルな宣言だけを集める
collectGDecl :: Program -> StateEnv ()
collectGDecl = mapM_ collectEdecl

collectEdecl :: EDecl -> StateEnv ()
collectEdecl (Decl p l) = mapM_ (appendEnv 0) (map (convVar p) l)
collectEdecl (FuncPrototype p ty nm args)
    = do {
        let { funcInfo = funcDecl ty args FuncProto } ;
        info <- findAtTheLevel 0 nm;
        case info of
          (Just i) -> if i == funcInfo
                      then return ()
                      else error $ concat [show p,
                                           ": invalid prototype decralation about ", nm]
          Nothing  -> appendEnv 0 (nm, funcInfo); }
collectEdecl (FuncDef p ty nm args stmt)
    = do {
        let { funcInfo = funcDecl ty args Func;
              err      = error $ concat [show p, ": invalid decralation - ", nm]; };
        info <- findAtTheLevel 0 nm;
        case info of
          (Just i) -> case i of
                        (FuncProto, ty) -> if ty == snd funcInfo
                                                then appendEnv 0 (nm, funcInfo)
                                                else err
                        (Func, _)       -> err
                        _               -> appendEnv 0 (nm, funcInfo)
          Nothing  -> appendEnv 0 (nm, funcInfo); }

funcDecl :: DeclType -> [(DeclType, Identifier)] -> Kind -> (Kind, CType)
funcDecl ty args ki = (ki, CFun (convType ty) $ map (convType . fst) args)

convVar :: SourcePos -> (DeclType, DirectDecl) -> Info
convVar p (t, d) = let ty = convType t in
                   if containVoid ty
                   then error $ concat [show p, ": variable contains void"]
                   else case d of
                          (Variable _ n)    -> (n, (Var, ty))
                          (Sequence _ n sz) -> (n, (Var, CArray ty sz))

convParm :: (DeclType, Identifier) -> Info
convParm (t, n) = (n, (Var, convType t))

convType :: DeclType -> CType
convType (DeclPointer ty) = CPointer (convType ty)
convType (DeclInt)        = CInt
convType (DeclVoid)       = CVoid

appendEnv :: Level -> Info -> StateEnv ()
appendEnv lev info = liftM (M.insertWith (++) lev [info]) get >>= put

appendWithDupCheck :: SourcePos -> Level -> [Info] -> StateEnv ()
appendWithDupCheck p lev = mapM_ f
    where f info = do i <- findAtTheLevel lev (fst info)
                      case i of
                        (Just _) -> error $ concat [show p,
                                                    ": duplicate variable decralations ",
                                                    fst info]
                        Nothing  -> appendEnv lev info

deleteLevel :: Level -> StateEnv ()
deleteLevel lev = (liftM (M.delete lev) get) >>= put

withEnv :: Level -> StateEnv () -> StateEnv a -> StateEnv a
withEnv lev mkenv body = mkenv >> body <* deleteLevel lev

find :: SourcePos -> Level -> Identifier -> StateEnv Info
find p lev name = do
  if lev <= (-1)
  then error $ concat [show p, ": varialble '", name, "' is not defined."]
  else do
    env <- get
    case (M.lookup lev env >>= lookup name) of
      (Just info) -> return (name, info)
      Nothing     -> find p (lev-1) name

findAtTheLevel :: Level -> Identifier -> StateEnv (Maybe (Kind, CType))
findAtTheLevel lev name = liftM (\e -> M.lookup lev e >>= lookup name) get

getType :: Info -> CType
getType = snd . snd

getRetType :: Info -> Maybe CType
getRetType i = case getType i of
                 (CFun ret _) -> Just ret
                 _            -> Nothing

containVoid :: CType -> Bool
containVoid (CVoid)          = True
containVoid (CArray CVoid _) = True
containVoid (CPointer CVoid) = True
containVoid _                = False
