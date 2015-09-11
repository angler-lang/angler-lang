{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE RankNTypes #-}
module Language.Angler.Parser.LP
        ( LP
        , LayoutContext(..)
        , LPState(..)
        , lp_buffer, lp_last_char, lp_loc, lp_bytes
        -- , lp_last_tk, lp_last_loc, lp_last_len
        , lp_lex_state, lp_context, lp_srcfiles
        , Byte

        , throwError
        , pushLP, popLP, peekLP
        -- , pushLexState, peekLexState, popLexState
        -- , pushContext, popContext
        , getOffside
        ) where

import           Language.Angler.SrcLoc
import           Language.Angler.Error

import           Control.Lens
import           Control.Monad.Except   (ExceptT(..), throwError)
import           Control.Monad.State    (StateT(..))
import           Data.Maybe             (fromJust)
import           Data.Word              (Word8)

import           Prelude                hiding (span)

-- LexerParser Monad
type LP a = StateT LPState (ExceptT (Located Error) Identity) a

type Byte = Word8

-- from GHC's Lexer
data LayoutContext
  = NoLayout            -- top level definitions
  | Layout Int
  deriving Show

-- from GHC's Lexer
data LPState
  = LPState
        { _lp_buffer    :: String
        , _lp_last_char :: Char
        , _lp_loc       :: SrcLoc               -- current location (end of prev token + 1)
        , _lp_bytes     :: [Byte]
        -- , _lp_last_tk   :: Maybe Token
        -- , _lp_last_loc  :: SrcSpan              -- location of previous token
        -- , _lp_last_len  :: Int                  -- length of previous token
        , _lp_lex_state :: [Int]                -- lexer states stack
        , _lp_context   :: [LayoutContext]      -- contexts stack
        , _lp_srcfiles  :: [String]
        }

makeLenses ''LPState

----------------------------------------
-- LPState's manipulation

pushLP :: Lens' LPState [a] -> a -> LP ()
pushLP lns x = lns %= cons x

peekLP :: Lens' LPState [a] -> LP a
peekLP lns = preuse (lns._head) >>= return . fromJust

popLP :: Lens' LPState [a] -> LP ()
popLP lns = use (lns._tail) >>= assign lns

getOffside :: SrcSpan -> LP Ordering
getOffside span = do
        stk <- use lp_context
        let indent = srcSpanSCol span
        return $ case stk of
                Layout indent' : _ -> compare indent indent'
                _                  -> GT
