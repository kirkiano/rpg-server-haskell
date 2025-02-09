{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE OverloadedStrings,
             RankNTypes,
             AllowAmbiguousTypes,
             MultiParamTypeClasses,
             TypeSynonymInstances,
             UndecidableInstances,
             FlexibleContexts,
             FlexibleInstances #-}

module RPGServer.DB.Caching ( CachedDB(..) ) where

import RPGServer.Common
import Prelude hiding              ( getContents )
import qualified RPGServer.Log     as L
import RPGServer.Listen.Auth       ( Auth(..) )
import RPGServer.DB.Class          ( MakeDB(..),
                                     AdminDB(..),
                                     PlayDB(..) )

data CachedDB d c = CachedDB {
  _db    :: d,
  _cache :: c
}


instance (MonadIO m,
          L.Log m L.Main,
          MakeDB m d di,
          MakeDB m c ci) =>
         MakeDB m (CachedDB d c) (di, ci) where
  connect (di, ci) = CachedDB <$> connect di <*> connect ci
  disconnect s     = do disconnect $ _db s
                        disconnect $ _cache s

type C d c = ReaderT (CachedDB d c)

------------------------------------------------------------

instance L.LogThreshold (ReaderT d m) =>
         L.LogThreshold (C d c m) where
  logThreshold = withReaderT _db L.logThreshold

instance (Monad m,
          L.Log (ReaderT d m) t) => L.Log (C d c m) t where
  logWrite lev = withReaderT _db . (L.logWrite lev)

------------------------------------------------------------

instance (Monad m,
          AdminDB (ReaderT d m),
          AdminDB (ReaderT c m)) => AdminDB (C d c m) where
  markLoggedInSet = mapExceptT (withReaderT _db) . markLoggedInSet


instance (Monad m,
          Auth (ReaderT d m),
          Auth (ReaderT c m)) => Auth (C d c m) where

  authUser creds = do
    db <- asks _db
    lift $ runReaderT (authUser creds) db


instance (Monad m,
          PlayDB (ReaderT d m),
          PlayDB (ReaderT c m)) => PlayDB (C d c m) where

  getThing tid = ExceptT $ do
    cache <- asks _cache
    etr   <- lift $ runReaderT (runExceptT $ getThing tid) cache
    either goSlow (return . Right) etr
    where
    goSlow _ = asks _db >>= \db -> lift $ runReaderT (runExceptT $ getThing tid) db

  loginCharacter b    = mapExceptT (withReaderT _db) . (loginCharacter b)
  getThingDescription = mapExceptT (withReaderT _db) . getThingDescription
  getTHandle          = mapExceptT (withReaderT _db) . getTHandle
  getCoPlace          = mapExceptT (withReaderT _db) . getCoPlace
  getCoExits          = mapExceptT (withReaderT _db) . getCoExits
  getAddress          = mapExceptT (withReaderT _db) . getAddress
  getCoContentHandles = mapExceptT (withReaderT _db) . getCoContentHandles
  getCoOccupantIDs    = mapExceptT (withReaderT _db) . getCoOccupantIDs
  setLocation pid     = mapExceptT (withReaderT _db) . (setLocation pid)
  setUtterance tid    = mapExceptT (withReaderT _db) . (setUtterance tid)
  updateThing         = mapExceptT (withReaderT _db) . updateThing

{-  
  setThing s t = do setThing (_db s) t
                    setThing (_cache s) t

  getLocation = getAndCache getLocation setLocation

  setLocation s tid pid = do setLocation (_db s) tid pid
                             setLocation (_cache s) tid pid

  getContents  = getContents . _db
  getOccupants = getOccupants . _db


getAndCache :: (DB m d pd,
                DB m c pc) =>
               (forall e. forall q. DB m e q => e -> i -> D m a) ->
               (c -> i -> a -> D m ()) ->
               CachedDB d c ->
               i ->
               D m a
getAndCache get set c i = either goSlow return =<< tryFast
  where tryFast  = lift $ runExceptT $ get (_cache c) i
        goSlow _ = helper (get $ _db c) (set (_cache c) i) i
        helper :: (Monad m) => (a -> m b) -> (b -> m ()) -> a -> m b
        helper getSlow setFast arg = do x <- getSlow arg
                                        setFast x
                                        return x
-}
