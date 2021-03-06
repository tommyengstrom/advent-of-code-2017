module AOC2017.Util (
    strip
  , iterateMaybe
  , (!!!)
  , dup
  , scanlT
  , scanrT
  ) where

import           Data.List
import           Data.Traversable
import qualified Data.Text        as T

-- | Strict (!!)
(!!!) :: [a] -> Int -> a
[] !!! _ = error "Out of range"
(x:_ ) !!! 0 = x
(x:xs) !!! n = x `seq` (xs !!! (n - 1))

strip :: String -> String
strip = T.unpack . T.strip . T.pack

iterateMaybe :: (a -> Maybe a) -> a -> [a]
iterateMaybe f x0 = x0 : unfoldr (fmap dup . f) x0

dup :: a -> (a, a)
dup x = (x, x)

scanlT :: Traversable t => (b -> a -> b) -> b -> t a -> t b
scanlT f z = snd . mapAccumL (\x -> dup . f x) z

scanrT :: Traversable t => (a -> b -> b) -> b -> t a -> t b
scanrT f z = snd . mapAccumR (\x -> dup . flip f x) z
