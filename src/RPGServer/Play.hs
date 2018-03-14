{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE FlexibleInstances,
             FlexibleContexts,
             UndecidableInstances #-}

module RPGServer.Play ( Play(..),
                        HasCID(..) ) where

import RPGServer.Common
import RPGServer.Util.Text
import Control.Monad.Trans.Class    ( lift )
import Data.List                    ( find )
import qualified Text.Regex         as R
import qualified System.Log         as L
import qualified RPGServer.DB.Error as D
import qualified RPGServer.DB.Class as DB
import qualified RPGServer.Log      as L
import qualified RPGServer.World    as W
import qualified RPGServer.Message  as M


class Monad m => HasCID m where
  getCID :: m W.CharacterID


type Forward m = M.Message -> [W.CharacterID] -> m ()


class HasCID m => Play m where
  whoAmI       :: D.D m W.ThingRec
  whereAmI     :: D.D m W.PlaceRec
  whoIsHere    :: D.D m [W.ThingRec]
  whatIsHere   :: D.D m [W.ThingRec]
  say          :: Forward m -> Text     -> D.D m ()
  exit         :: Forward m -> W.ExitID -> D.D m ()
  quit         :: Forward m             -> D.D m M.Message
  join         :: Forward m             -> D.D m M.Message


instance (DB.DB m,
          HasCID m,
          L.Log m L.Game) => Play m where

  whoAmI = DB.getThing =<< lift getCID

  whereAmI = do cid <- lift getCID
                DB.getLocation cid >>= DB.getPlace

  whatIsHere = do cid <- lift getCID
                  DB.getLocation cid >>= DB.getContents

  exit fw eid = do
    me <- whoAmI
    p  <- whereAmI
    let mExit  = find ((== eid) . W.exitID) $ W.exits p
        err    = throwE $ D.InvalidExitID eid
        cont e = do
          oldRecips <- map W.idn <$> whoIsHere
          let (did, dname) = W.exitDestination e
          DB.setLocation (W.idn me) did
          newRecips <- map W.idn <$> whoIsHere
          lift $ fw (M.ExitedTo    (W.idn me)      dname) oldRecips
          lift $ fw (M.EnteredFrom        me  $ W.name p) newRecips
    maybe err cont mExit

  whoIsHere = do cid <- lift getCID
                 DB.getLocation cid >>= DB.getOccupants

  say fw s = maybe (return ()) bcast nonwhite where
    nonwhite = R.matchRegex (R.mkRegex "[^ ]") $ unpack s
    bcast _  = do cid    <- lift getCID
                  recips <- map W.idn <$> whoIsHere
                  lift $ fw (M.Said cid s) recips

  join = joinOrQuit True

  quit = joinOrQuit False


joinOrQuit :: (DB.DB m, HasCID m, L.Log m L.Game)
              =>
              Bool ->
              Forward m ->
              D.D m M.Message
joinOrQuit b fw = do
  cid <- lift getCID
  recips <- map W.idn <$> whoIsHere
  let m = (if b then M.Joined else M.Disjoined) cid
  lift $ fw m recips
  return m