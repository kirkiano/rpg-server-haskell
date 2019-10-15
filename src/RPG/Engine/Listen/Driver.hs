
module RPG.Engine.Listen.Driver ( driverAction ) where

import RPG.Engine.Common
import Control.Monad.Trans.Except               ( catchE )
import qualified Data.Set                       as S
import qualified System.Log                     as L
-- import RPG.Engine.Util.Fork                     ( HasFork )
import qualified RPG.Engine.Log                 as L
import qualified SendReceive                    as SR
import RPG.Request                              ( Request(..),
                                                  PlayerRequest(..))
import RPG.Message                              ( Message(..) )


driverAction :: (MonadIO m,
--                 HasFork m,
                 SR.WaitReceiveFrom a m Request,
                 SR.SendTo a m Message,
                 SR.Disconnect m a,
                 L.Log m L.Drive)
                =>
                ((Request, Message -> m ()) -> m ()) -> a -> m ()
driverAction sendToGameLoop driver = void . runExceptT . loop $ S.empty where
  loop cids0 = catchE processNextRequest dismiss where
    processNextRequest = do
      q     <- SR.waitRecv driver
      cids1 <- lift $ updateCids q
      lift $ sendToGameLoop (q, sendDriver)
      loop cids1
    dismiss e = lift $ do -- driver gone, so dismiss it & shut down active cids
      SR.disconnect driver . Just . show $ e
      mapM_ (sendToGameLoop . (, sendDriver) . (flip PlayerRequest Quit)) cids0
    updateCids (PlayerRequest cid Join) = do logReg True  cid
                                             return $ S.insert cid cids0
    updateCids (PlayerRequest cid Quit) = do logReg False cid
                                             return $ S.delete cid cids0
    updateCids _                        = do return cids0
    logReg isReg = L.log L.Info . ctor where
      ctor = if isReg then L.RegisteringPlayer else L.DeregisteringPlayer
  sendDriver = void . runExceptT . (SR.send driver)