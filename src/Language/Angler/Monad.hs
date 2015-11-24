{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE RankNTypes #-}

module Language.Angler.Monad
    ( foldActions

    , pushM, peekM, popM

    , STWarnings(..)
    , warn

    , STErrors(..)
    , addError

    , throwError

    , STScopedTable(..)
    , lookupSc, lookupAndHandleSc
    , insertSc, insertAndHandleSc, replaceSc
    , enterSc, exitSc, bracketSc, topSc
    ) where

import           Language.Angler.Error
import           Language.Angler.SrcLoc
import           Language.Angler.ScopedTable

import           Control.Lens

import           Control.Monad               (when)
import           Control.Monad.State         (MonadState)
import           Control.Monad.Except        (throwError)

import           Data.Foldable               (foldl')
import           Data.Maybe                  (isJust, isNothing, fromMaybe)

import           Prelude                     hiding (lookup)

foldActions :: Monad m => [a -> m a] -> a -> m a
foldActions acts x = foldl' (>>=) (return x) acts

--------------------------------------------------------------------------------

pushM :: MonadState s m => Lens' s [a] -> a -> m ()
pushM lns x = lns %= cons x

peekM :: MonadState s m => Lens' s [a] -> m a
peekM lns = fromMaybe (error "Monad.peekM: Nothing") <$> preuse (lns._head)

popM  :: MonadState s m => Lens' s [a] -> m ()
popM lns = lns %= tail

--------------------------------------------------------------------------------

class STWarnings st where
        st_warnings :: Lens' st [Located Warning]

warn :: (STWarnings s, MonadState s m) => Located Warning -> m ()
warn w = st_warnings %= (|> w)

----------------------------------------

class STErrors st where
        st_errors :: Lens' st [Located Error]

addError :: (STErrors s, MonadState s m) => Located Error -> m ()
addError e = st_errors %= (|> e)

--------------------------------------------------------------------------------

class STScopedTable st sym | st -> sym where
        st_table :: Lens' st (ScopedTable sym)

lookupSc :: (STScopedTable s sym, MonadState s m) => String -> m (Maybe sym)
lookupSc = uses st_table . lookup

lookupAndHandleSc :: (STScopedTable s sym, MonadState s m, STErrors s)
                  => String -> SrcSpan -> m (Maybe sym)
lookupAndHandleSc str spn = do
        msym <- lookupSc str
        when (isNothing msym)
                ((addError . Loc spn . CheckError . CErrNotInSymbolTable) str)
        return msym

insertSc :: (STScopedTable s sym, MonadState s m) => String -> sym -> m (Maybe Error)
insertSc str sym = do
        eitTab <- uses st_table (safeInsert str sym)
        case eitTab of
                Left err   -> return (Just err)
                Right tab' -> assign st_table tab' >> return Nothing

insertAndHandleSc :: (STScopedTable s sym, MonadState s m, STErrors s)
                  => String -> sym -> SrcSpan -> m ()
insertAndHandleSc str sym spn = do
        merr <- insertSc str sym
        when (isJust merr) $ do
                let Just err = merr
                addError (Loc spn err)

replaceSc :: (STScopedTable s sym, MonadState s m) => String -> sym -> m ()
replaceSc str sym = st_table %= (insert str sym)

enterSc :: (STScopedTable s sym, MonadState s m) => m ()
enterSc = st_table %= enterScope

exitSc :: (STScopedTable s sym, MonadState s m) => m ()
exitSc = st_table %= exitScope

bracketSc :: (STScopedTable s sym, MonadState s m) => m a -> m a
bracketSc act = enterSc >> act >>= \r -> exitSc >> return r

topSc :: (STScopedTable s sym, MonadState s m) => m (ScopedTable sym)
topSc = uses st_table topScope
