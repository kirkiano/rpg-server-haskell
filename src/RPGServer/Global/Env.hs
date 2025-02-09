{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE OverloadedStrings,
             TypeSynonymInstances,
             MultiParamTypeClasses,
             UndecidableInstances,
             FlexibleContexts,
             FlexibleInstances #-}

module RPGServer.Global.Env ( Env(..),
                              G,
                              runG,
                              gCatch,
                              gBracket,
                              gBracketOnError,
                              createEnv,
                              destroyEnv ) where

import RPGServer.Common
import Prelude hiding                       ( getContents )
import GHC.IO.Handle                        ( Handle )
import qualified Forwarder.Log              as FL
import qualified RPGServer.Log              as L
import qualified RPGServer.Global.Settings  as S
import RPGServer.World                      ( CharacterID )
import RPGServer.Message                    ( Message )
import RPGServer.Listen.Auth                ( Auth(..) )
import RPGServer.DB.Class                   ( AdminDB(..),
                                              PlayDB(..),
                                              MakeDB(..) )
import qualified RPGServer.DB.Postgres      as PG


type DBase = PG.Conn

data Env = Env { dBase   :: DBase,
                 saveUtt :: Bool }
         deriving Show

------------------------------------------------------------

type G = ReaderT Env L.L

runG :: Env -> (L.Level, Handle) -> G a -> IO a
runG env lh g = runReaderT (runReaderT g env) lh

gCatch :: Exception e => G a -> (e -> G a) -> G a
gCatch act hdl = do
  env <- ask
  lh  <- lift ask
  liftIO $ catch (runG env lh act) (\e -> runG env lh (hdl e))

gBracket :: G a -> (a -> G ()) -> (a -> G b) -> G b
gBracket create destroy action = do
  env <- ask
  lh <- lift ask
  liftIO $ bracket
    (runG env lh create)
    (\r -> runG env lh $ destroy r)
    (\r -> runG env lh $ action r)

gBracketOnError :: G a -> (a -> G ()) -> (a -> G b) -> G b
gBracketOnError create destroy action = do
  env <- ask
  lh <- lift ask
  liftIO $ bracketOnError
    (runG env lh create)
    (\r -> runG env lh $ destroy r)
    (\r -> runG env lh $ action r)

------------------------------------------------------------

instance L.LogThreshold G where
  logThreshold = lift L.logThreshold

instance L.Log G L.Connection where
  logWrite lev = withReaderT dBase . (L.logWrite lev)

instance L.Log G L.Main where
  logWrite lev = lift . (L.logWrite lev)

instance L.Log G L.Transmission where
  logWrite lev = lift . (L.logWrite lev)

instance L.Log G L.Game where
  logWrite lev = lift . (L.logWrite lev)

instance L.Log G L.Auth where
  logWrite lev = lift . (L.logWrite lev)

instance L.Log G L.General where
  logWrite lev = lift . (L.logWrite lev)

------------------------------------------------------------

instance L.Log G (FL.ForwardLog CharacterID m Message) where
  logWrite lev = lift . (L.logWrite lev)

------------------------------------------------------------

instance Auth G where
  authUser            = withReaderT dBase . authUser

instance AdminDB G where
  markLoggedInSet     = mapExceptT (withReaderT dBase) . markLoggedInSet


instance PlayDB G where
  loginCharacter b    = mapExceptT (withReaderT dBase) . (loginCharacter b)
  getThing            = mapExceptT (withReaderT dBase) . getThing
  getThingDescription = mapExceptT (withReaderT dBase) . getThingDescription
  getTHandle          = mapExceptT (withReaderT dBase) . getTHandle
  getAddress          = mapExceptT (withReaderT dBase) . getAddress
  getCoPlace          = mapExceptT (withReaderT dBase) . getCoPlace
  getCoExits          = mapExceptT (withReaderT dBase) . getCoExits
  getCoOccupantIDs    = mapExceptT (withReaderT dBase) . getCoOccupantIDs
  getCoContentHandles = mapExceptT (withReaderT dBase) . getCoContentHandles
  setLocation pid     = mapExceptT (withReaderT dBase) . (setLocation pid)
  updateThing         = mapExceptT (withReaderT dBase) . updateThing
  setUtterance tid s  = do
    save <- lift $ asks saveUtt
    when save $ mapExceptT (withReaderT dBase) (setUtterance tid s)


createEnv :: (MonadIO m, L.Log m L.Main) => ReaderT S.Settings m Env
createEnv = Env <$> connDB <*> asks S.saveUtterances where
    connDB = lift . connect =<< asks S.pgSettings


destroyEnv :: (MonadIO m, L.Log m L.Main) => Env -> m ()
destroyEnv = disconnect . dBase
