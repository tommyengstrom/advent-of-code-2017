{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TemplateHaskell       #-}

module AOC2017.Day18 (day18a, day18b) where

import           AOC2017.Types             (Challenge)
import           AOC2017.Util.Accum        (AccumT(..), execAccumT, look, add)
import           AOC2017.Util.Tape         (Tape(..), HasTape(..), move, unsafeTape)
import           Control.Applicative       (many, empty)
import           Control.Lens              (makeClassy, use, at, non, (%=), use, (.=), (<>=), zoom)
import           Control.Monad             (guard, when)
import           Control.Monad.Prompt      (Prompt, prompt, runPromptM)
import           Control.Monad.State       (MonadState(get,put), StateT(..), State, execStateT, evalState)
import           Control.Monad.Trans.Class (MonadTrans(lift))
import           Control.Monad.Trans.Maybe (MaybeT(..))
import           Control.Monad.Writer      (MonadWriter(..), WriterT(..), Writer, execWriter)
import           Data.Char                 (isAlpha)
import           Data.Kind                 (Type)
import           Data.Maybe                (fromJust)
import           Data.Monoid               (First(..), Last(..))
import qualified Data.Map                  as M
import qualified Data.Vector.Sized         as V

{-
******************
*  The Language  *
******************
-}

type Addr = Either Char Int

addr :: String -> Addr
addr [c] | isAlpha c = Left c
addr str = Right (read str)

data Op = OSnd Addr
        | OBin (Int -> Int -> Int) Char Addr
        | ORcv Char
        | OJgz Addr Addr

parseOp :: String -> Op
parseOp inp = case words inp of
    "snd":(addr->c):_           -> OSnd c
    "set":(x:_):(addr->y):_     -> OBin (const id) x y
    "add":(x:_):(addr->y):_     -> OBin (+)        x y
    "mul":(x:_):(addr->y):_     -> OBin (*)        x y
    "mod":(x:_):(addr->y):_     -> OBin mod        x y
    "rcv":(x:_):_               -> ORcv x
    "jgz":(addr->x):(addr->y):_ -> OJgz x y
    _                           -> error "Bad parse"

parse :: String -> Tape Op
parse = unsafeTape . map parseOp . lines

{-
**************************
*  The Abstract Machine  *
**************************
-}

-- | Abstract data type describing "IO" available to the abstract machine
data Command :: Type -> Type where
    CRcv :: Int -> Command Int    -- ^ input is current value of buffer
    CSnd :: Int -> Command ()     -- ^ input is thing being sent

type Machine = Prompt Command

rcvMachine :: Int -> Machine Int
rcvMachine = prompt . CRcv

sndMachine :: Int -> Machine ()
sndMachine = prompt . CSnd

data ProgState = PS { _psTape :: Tape Op
                    , _psRegs :: M.Map Char Int
                    }
makeClassy ''ProgState

-- | Context in which a 'Duet' program runs
type Duet = MaybeT (StateT ProgState Machine)
execDuet :: Duet a -> ProgState -> Machine ProgState
execDuet = execStateT . runMaybeT

-- | Single step through program tape.
stepTape :: Duet ()
stepTape = use (psTape . tFocus) >>= \case
    OSnd x -> do
      lift . lift . sndMachine =<< addrVal x
      advance 1
    OBin f x y -> do
      yVal <- addrVal y
      psRegs . at x . non 0 %= (`f` yVal)
      advance 1
    ORcv x -> do
      y <- lift . lift . rcvMachine =<< use (psRegs . at x . non 0)
      psRegs . at x . non 0 .= y
      advance 1
    OJgz x y -> do
      xVal <- addrVal x
      moveAmt <- if xVal > 0
                   then addrVal y
                   else return 1
      advance moveAmt
  where
    addrVal (Left r)  = use (psRegs . at r . non 0)
    addrVal (Right x) = return x
    advance n = do
      Just t' <- move n <$> use psTape
      psTape .= t'

{-
************************
*  Context for Part A  *
************************
-}

-- | Context in which to interpret Command for Part A
--
-- Accum parameter is the most recent sent item.  Writer parameter is the
-- first Rcv'd item.
type PartA = AccumT (Last Int) (Writer (First Int))
execPartA :: PartA a -> Int
execPartA = fromJust . getFirst . execWriter . flip execAccumT mempty

-- | Interpet Command for Part A
interpretA :: Command a -> PartA a
interpretA = \case
    CRcv x -> do
      when (x /= 0) $
        tell . First . getLast =<< look
      return x
    CSnd x -> add (pure x)

day18a :: Challenge
day18a = show . execPartA
       . runPromptM interpretA
       . execDuet (many stepTape)  -- stepTape until program terminates
       . (`PS` M.empty) . parse

{-
************************
*  Context for Part B  *
************************
-}

-- | Context in which to interpret Command for Part B
type PartB s = MaybeT (State s)

-- | Interpet Command for Part B, with an [Int] writer side-channel
interpretB
    :: Command a
    -> WriterT [Int] (PartB [Int]) a
interpretB = \case
    CSnd x -> tell [x]
    CRcv _ -> get >>= \case
      []   -> empty
      x:xs -> put xs >> return x

data Thread = T { _tState   :: ProgState
                , _tBuffer  :: [Int]
                }
makeClassy ''Thread

-- | Single step through a thread.  Nothing = either the thread terminates,
-- or requires extra input.
stepThread :: PartB Thread [Int]
stepThread = do
    machine   <- execDuet stepTape <$> use tState
    (ps, out) <- runWriterT . zoom tBuffer
               $ runPromptM interpretB machine
    tState .= ps
    return out

type MultiState = V.Vector 2 Thread

-- | Single step through both threads.  Nothing = both threads terminate
stepThreads :: PartB MultiState Int
stepThreads = do
    outA <- zoom (V.ix 0) $ concat <$> many stepThread
    outB <- zoom (V.ix 1) $ concat <$> many stepThread
    V.ix 0 . tBuffer <>= outB
    V.ix 1 . tBuffer <>= outA
    guard . not $ null outA && null outB
    return $ length outB

day18b :: Challenge
day18b (parse->t) = show . sum . concat
                  . evalState (runMaybeT (many stepThreads))
                  $ ms
  where
    Just ms = V.fromList [ T (PS t (M.singleton 'p' 0)) []
                         , T (PS t (M.singleton 'p' 1)) []
                         ]

