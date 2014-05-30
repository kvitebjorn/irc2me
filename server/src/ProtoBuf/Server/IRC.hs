{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DataKinds #-}

module ProtoBuf.Server.IRC where

import Data.ProtocolBuffers
import Data.Monoid
import Data.Text          (Text)

import GHC.Generics (Generic)

import qualified Network.IRC.ByteString.Parser as I
import qualified IRC.Types                     as IRC
import           ProtoBuf.Instances ()
import           ProtoBuf.Helper

--------------------------------------------------------------------------------
-- IRC messages

data IrcMsgType
  = Ty_PrivMsg
  | Ty_NoticeMsg
  | Ty_JoinMsg
  | Ty_PartMsg
  | Ty_KickMsg
  | Ty_QuitMsg
  | Ty_MOTDMsg
  | Ty_TopicMsg
  | Ty_NickMsg
  | Ty_NamreplyMsg
  | Ty_ErrorMsg
  | Ty_RawMsg
  deriving (Eq, Enum, Show)

data PB_Namreply = PB_Namreply
  { namreply_name     :: Required 1 (Value Text)
  , namreply_userflag :: Optional 2 (Enumeration IRC.Userflag)
  }
  deriving (Eq, Show, Generic)

instance Encode PB_Namreply
instance Decode PB_Namreply

data PB_IrcMessage = PB_IrcMessage
  { -- message type
    irc_msg_type        :: Required 1  (Enumeration IrcMsgType)
    -- raw messages
  , irc_msg_from        :: Optional 5 (Value Text) -- either...
  , irc_msg_servername  :: Optional 6 (Value Text) -- ...or
  , irc_msg_command     :: Optional 7 (Value Text)
  , irc_msg_params      :: Repeated 8 (Value Text)
  , irc_msg_content     :: Optional 9 (Value Text)
    -- privmsg/notice
  , irc_msg_to          :: Optional 10 (Value Text)
    -- nick change + namreply
  , irc_msg_new_nick    :: Optional 21 (Value Text)
  , irc_msg_namreply    :: Repeated 22 (Message PB_Namreply)
    -- join/part/kick/quit
  , irc_msg_channels    :: Repeated 30 (Value Text)
  , irc_msg_who         :: Optional 31 (Value Text)
    -- motd/topic
  , irc_msg_notopic     :: Optional 42 (Value Bool)
  }
  deriving (Show, Generic)

instance Encode PB_IrcMessage
instance Decode PB_IrcMessage

emptyIrcMessage :: IrcMsgType -> PB_IrcMessage
emptyIrcMessage ty = PB_IrcMessage
  { -- msg type
    irc_msg_type        = putField ty
    -- raw messages
  , irc_msg_from        = mempty
  , irc_msg_servername  = mempty
  , irc_msg_command     = mempty
  , irc_msg_params      = mempty
  , irc_msg_content     = mempty
    -- privmsg/notice
  , irc_msg_to          = mempty
    -- nick change
  , irc_msg_new_nick    = mempty
  , irc_msg_namreply    = mempty
    -- join/part/kick
  , irc_msg_channels    = mempty
  , irc_msg_who         = mempty
    -- motd/topic
  , irc_msg_notopic     = mempty
  }

encodeIrcMessage :: IRC.Message -> PB_IrcMessage
encodeIrcMessage msg =
  case msg of
    IRC.PrivMsg from to cont ->
      let (nick,srv) = splitFrom from
       in (emptyIrcMessage Ty_PrivMsg)
            { irc_msg_from       = nick
            , irc_msg_servername = srv
            , irc_msg_to         = putBS to
            , irc_msg_content    = putBS cont
            }
    IRC.NoticeMsg from to cont ->
      let (nick,srv) = splitFrom from
       in (emptyIrcMessage Ty_NoticeMsg)
            { irc_msg_from       = nick
            , irc_msg_servername = srv
            , irc_msg_to         = putBS to
            , irc_msg_content    = putBS cont
            }
    IRC.JoinMsg chans (fmap I.userNick -> who) ->
      (emptyIrcMessage Ty_JoinMsg)
        { irc_msg_channels = putBSs chans
        , irc_msg_who      = putBSMaybe who
        }
    IRC.PartMsg chan (fmap I.userNick -> who) ->
      (emptyIrcMessage Ty_PartMsg)
        { irc_msg_channels = putBSs [chan]
        , irc_msg_who      = putBSMaybe who
        }
    IRC.KickMsg chan who comment ->
      (emptyIrcMessage Ty_KickMsg)
        { irc_msg_channels = putBSs [chan]
        , irc_msg_who      = putBSMaybe who
        , irc_msg_content  = putBSMaybe comment
        }
    IRC.QuitMsg who comment ->
      (emptyIrcMessage Ty_QuitMsg)
        { irc_msg_who      = putBSMaybe (I.userNick `fmap` who)
        , irc_msg_content  = putBSMaybe comment
        }
    IRC.MOTDMsg motd ->
      (emptyIrcMessage Ty_MOTDMsg)
        { irc_msg_content = putBS motd
        }
    IRC.TopicMsg chan topic ->
      (emptyIrcMessage Ty_TopicMsg)
        { irc_msg_channels = putBSs [chan]
        , irc_msg_content  = putBSMaybe topic
        }
    IRC.NickMsg (fmap I.userNick -> old) new ->
      (emptyIrcMessage Ty_NickMsg)
        { irc_msg_from     = putBSMaybe old
        , irc_msg_new_nick = putBS new
        }
    IRC.NamreplyMsg chan names ->
      (emptyIrcMessage Ty_NamreplyMsg)
        { irc_msg_channels = putBSs [chan]
        , irc_msg_namreply = putNamreply names
        }
    IRC.ErrorMsg code ->
      (emptyIrcMessage Ty_ErrorMsg)
        { irc_msg_command = putBS code
        }
    IRC.OtherMsg mfrom cmd params content ->
      let (nick,srv) = maybe (putField Nothing, putField Nothing)
                             splitFrom
                             mfrom
       in (emptyIrcMessage Ty_RawMsg)
            { irc_msg_from       = nick
            , irc_msg_servername = srv
            , irc_msg_command    = putBS cmd
            , irc_msg_params     = putBSs params
            , irc_msg_content    = putBS content
            }

--
-- Helper
--

putNamreply :: [(IRC.Nickname, Maybe IRC.Userflag)]
            -> Repeated a (Message PB_Namreply)
putNamreply n = putField $ map `flip` n $ \(name, uf) ->
  PB_Namreply (putField $ decodeUtf8 name) (putField uf)