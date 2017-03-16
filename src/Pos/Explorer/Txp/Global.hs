{-# LANGUAGE ScopedTypeVariables #-}

-- | Explorer's global Txp (expressed as settings).

module Pos.Explorer.Txp.Global
       ( explorerTxpGlobalSettings
       ) where

import           Universum

import qualified Data.HashMap.Strict   as HM

import           Pos.Core              (HeaderHash, headerHash)
import           Pos.DB                (SomeBatchOp (..))
import           Pos.Slotting          (MonadSlots, currentTimeSlotting)
import           Pos.Txp               (ApplyBlocksSettings (..), TxpBlund,
                                        TxpGlobalRollbackMode, TxpGlobalSettings (..),
                                        applyBlocksWith, blundToAuxNUndo,
                                        genericToilModifierToBatch, runToilAction,
                                        txpGlobalSettings)
import           Pos.Txp.Core          (TxAux, TxUndo)
import           Pos.Util              (NE, NewestFirst (..))
import qualified Pos.Util.Modifier     as MM

import qualified Pos.Explorer.DB       as GS
import           Pos.Explorer.Txp.Toil (EGlobalToilMode, ExplorerExtra (..), eApplyToil,
                                        eRollbackToil)

-- | Settings used for global transactions data processing used by a
-- simple full node.
explorerTxpGlobalSettings :: TxpGlobalSettings
explorerTxpGlobalSettings =
    -- verification is same
    txpGlobalSettings
    { tgsApplyBlocks = applyBlocksWith eApplyBlocksSettings
    , tgsRollbackBlocks = rollbackBlocks
    }

eApplyBlocksSettings
    :: forall m.
       (EGlobalToilMode m, MonadSlots m)
    => ApplyBlocksSettings ExplorerExtra m
eApplyBlocksSettings =
    ApplyBlocksSettings
    { absApplySingle = applyBlund
    , absExtraOperations = const mempty
    }

extraOps :: ExplorerExtra -> SomeBatchOp
extraOps (ExplorerExtra em (HM.toList -> histories)) =
    SomeBatchOp $
    map GS.DelTxExtra (MM.deletions em) ++
    map (uncurry GS.AddTxExtra) (MM.insertions em) ++
    map (uncurry GS.UpdateAddrHistory) histories

applyBlund :: (MonadSlots m, EGlobalToilMode m) => TxpBlund -> m ()
applyBlund blund = do
    curTime <- currentTimeSlotting
    uncurry (eApplyToil curTime) $ blundToAuxNUndoWHash blund

rollbackBlocks
    :: TxpGlobalRollbackMode m
    => NewestFirst NE TxpBlund -> m SomeBatchOp
rollbackBlocks blunds =
    (genericToilModifierToBatch extraOps) . snd <$>
    runToilAction (mapM (eRollbackToil . blundToAuxNUndo) blunds)

-- Zip block's TxAuxes and also add block hash
blundToAuxNUndoWHash :: TxpBlund -> ([(TxAux, TxUndo)], HeaderHash)
blundToAuxNUndoWHash blund@(blk, _) =
    (blundToAuxNUndo blund, either headerHash (headerHash . fst) blk)
