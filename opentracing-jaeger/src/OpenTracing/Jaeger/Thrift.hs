{-# LANGUAGE TupleSections #-}

module OpenTracing.Jaeger.Thrift
    ( toThriftSpan
    , toThriftTags
    , toThriftProcess
    , toThriftBatch
    )
where

import           Data.ByteString.Lazy       (toStrict)
import           Control.Lens
import           Data.Bool                  (bool)
import           Data.Foldable
import           Data.Int                   (Int64)
import           Data.Text                  (Text)
import           Data.Text.Lazy.Builder     (toLazyText)
import           Data.Text.Lazy.Builder.Int (decimal)
import           Data.Text.Lens
import           Data.Vector                (Vector)
import qualified Data.Vector                as Vector
import           Data.Vector.Lens           (vector)
import           GHC.Stack                  (prettyCallStack)
import           Jaeger.Types
    ( Batch (..)
    , Log (..)
    , Process (..)
    , Span (..)
    , SpanRef (..)
    , Tag (..)
    )
import qualified Jaeger.Types               as Thrift
import           OpenTracing.Log
import           OpenTracing.Span
import           OpenTracing.Tags
import           OpenTracing.Time
import           OpenTracing.Types          (TraceID (..))


toThriftSpan :: FinishedSpan -> Thrift.Span
toThriftSpan s = Thrift.Span
    { span_traceIdLow    = view (spanContext . to traceIdLo') s
    , span_traceIdHigh   = view (spanContext . to traceIdHi') s
    , span_spanId        = view (spanContext . to ctxSpanID') s
    , span_parentSpanId  = maybe 0 (ctxSpanID' . refCtx) . findParent
                         $ view spanRefs s
    , span_operationName = view spanOperation s
    , span_references    = view ( spanRefs
                                . to (map toThriftSpanRef . toList)
                                . vector
                                . re _Just
                                )
                                s
    , span_flags         = view ( spanContext
                                . ctxSampled
                                . re _IsSampled
                                . to (bool 0 1)
                                )
                                s
    , span_startTime     = view (spanStart . to micros) s
    , span_duration      = view (spanDuration . to micros) s
    , span_tags          = view (spanTags . to toThriftTags . re _Just) s
    , span_logs          = Just
                         . Vector.fromList
                         . foldr' (\r acc -> toThriftLog r : acc) []
                         $ view spanLogs s
    }

toThriftSpanRef :: Reference -> Thrift.SpanRef
toThriftSpanRef ref = Thrift.SpanRef
    { spanRef_refType     = toThriftRefType ref
    , spanRef_traceIdLow  = traceIdLo' (refCtx ref)
    , spanRef_traceIdHigh = traceIdHi' (refCtx ref)
    , spanRef_spanId      = ctxSpanID' (refCtx ref)
    }

toThriftRefType :: Reference -> Thrift.SpanRefType
toThriftRefType (ChildOf     _) = Thrift.CHILD_OF
toThriftRefType (FollowsFrom _) = Thrift.FOLLOWS_FROM

toThriftTags :: Tags -> Vector Thrift.Tag
toThriftTags = ifoldMap (\k v -> Vector.singleton (toThriftTag k v)) . fromTags

toThriftTag :: Text -> TagVal -> Thrift.Tag
-- acc. to https://github.com/opentracing/specification/blob/8d634bc7e3e73050f6ac1006858cddac8d9e0abe/semantic_conventions.yaml
-- "http.status_code" is supposed to be integer-valued. Jaeger, however, drops
-- the value (nb. _not_ the tag key) unless it is a string.
toThriftTag HttpStatusCodeKey (IntT v) = Thrift.Tag
    { tag_key     = HttpStatusCodeKey
    , tag_vType   = Thrift.STRING
    , tag_vStr    = Just . view strict . toLazyText . decimal $ v
    , tag_vDouble = Nothing
    , tag_vBool   = Nothing
    , tag_vLong   = Nothing
    , tag_vBinary = Nothing
    }
toThriftTag k v =
  Thrift.Tag
  {
    tag_key = k
  , tag_vType = case v of
      BoolT   _ -> Thrift.BOOL
      StringT _ -> Thrift.STRING
      IntT    _ -> Thrift.LONG
      DoubleT _ -> Thrift.DOUBLE
      BinaryT _ -> Thrift.BINARY
  , tag_vStr = case v of
      StringT x -> Just x
      _ -> Nothing
  , tag_vDouble = case v of
      DoubleT x -> Just x
      _ -> Nothing
  , tag_vBool = case v of
      BoolT x -> Just x
      _ -> Nothing
  , tag_vLong = case v of
      IntT x -> Just x
      _ -> Nothing
  , tag_vBinary = case v of
      BinaryT x -> Just (toStrict x)
      _ -> Nothing
  }

toThriftLog :: LogRecord -> Thrift.Log
toThriftLog r = Thrift.Log
    { log_timestamp = view (logTime . to micros) r
    , log_fields    = foldMap ( Vector.singleton
                              . uncurry toThriftTag
                              . asTag
                              )
                    $ view logFields r
    }
  where
    asTag f = (logFieldLabel f,) . StringT $ case f of
        LogField _ v -> view packed (show v)
        Event      v -> v
        Message    v -> v
        Stack      v -> view packed (prettyCallStack v)
        ErrKind    v -> v
        ErrObj     v -> view packed (show v)

toThriftProcess :: Text -> Tags -> Thrift.Process
toThriftProcess srv tags = Thrift.Process
    { process_serviceName = srv
    , process_tags        = Just $ toThriftTags tags
    }

toThriftBatch :: Thrift.Process -> Vector FinishedSpan -> Thrift.Batch
toThriftBatch tproc spans = Thrift.Batch
    { batch_process = tproc
    , batch_spans   = toThriftSpan <$> spans
    , batch_seqNo   = Nothing
    , batch_stats   = Nothing
    }

traceIdLo' :: SpanContext -> Int64
traceIdLo' = fromIntegral . traceIdLo . ctxTraceID

traceIdHi' :: SpanContext -> Int64
traceIdHi' = maybe 0 fromIntegral . traceIdHi . ctxTraceID

ctxSpanID' :: SpanContext -> Int64
ctxSpanID' = fromIntegral . ctxSpanID
