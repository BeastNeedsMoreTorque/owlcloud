{-# LANGUAGE OverloadedStrings #-}

module OwlCloud.Common where

import           Control.Monad              (liftM)
import           Data.Proxy
import           Data.Set                   (Set)
import qualified Data.Set                   as Set
import           Import
import           Network.HTTP.Client        (Manager)
import           OwlCloud.Types
import           Servant
import           Servant.Client
import           System.IO.Unsafe           (unsafeInterleaveIO,
                                             unsafePerformIO)

-- | Database

data State = State
    { validTokens :: Set SigninToken
    , albumsList  :: [Album] }

db :: TVar State
db = unsafePerformIO (unsafeInterleaveIO (newTVarIO (State Set.empty initialAlbums)))
  where
    initialAlbums = [Album [Photo "Scating" "http://i.imgur.com/PuhhmQi.jpg"
                           ,Photo "Taking shower" "http://i.imgur.com/v5kqUIM.jpg"]
                    ,Album [Photo "About to fly" "http://i.imgur.com/3hRAGWJ.png"
                           ,Photo "Selfie" "http://i.imgur.com/ArZrhR6.jpg"]]
{-# NOINLINE db #-}

-- | Request-ready microservices API

-- Users API

apiUsersOwlIn :<|> apiUsersOwlOut :<|> apiUsersTokenValidity =
    client (Proxy::Proxy UsersAPI)
usersBaseUrl :: BaseUrl
usersBaseUrl = BaseUrl Http "localhost" 8082 ""

-- Albums API

apiAlbumsList =
    client (Proxy::Proxy AlbumsAPI)
albumsBaseUrl = BaseUrl Http "localhost" 8083 ""

-- | Utils

fly :: (Show b, MonadIO m)
    => ExceptT ServantError m b
    -> ExceptT ServantErr m b
fly apiReq =
    either logAndFail return =<< ExceptT (liftM Right (runExceptT apiReq))
  where
    logAndFail e = do
        liftIO (putStrLn ("Got internal-api error: " ++ show e))
        throwE internalError
    internalError = ServantErr 500 "CyberInternal MicroServer MicroError" "" []

checkValidity :: Manager
              -> Maybe SigninToken
              -> ExceptT ServantErr IO ()
checkValidity mgr =
    maybe (throwE (ServantErr 400 "Please, provide an authorization token" "" []))
          (\t -> fly (apiUsersTokenValidity t mgr usersBaseUrl) >>= handleValidity)
  where
    handleValidity (TokenValidity True) = return ()
    handleValidity (TokenValidity False) =
        throwE (ServantErr 400 "Your authorization token is invalid" "" [])
