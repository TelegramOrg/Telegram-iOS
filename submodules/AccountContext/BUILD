load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "AccountContext",
    module_name = "AccountContext",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/TelegramAudio:TelegramAudio",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/TemporaryCachedPeerDataManager:TemporaryCachedPeerDataManager",
        "//submodules/DeviceLocationManager:DeviceLocationManager",
        "//submodules/MediaPlayer:UniversalMediaPlayer",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/MusicAlbumArtResources:MusicAlbumArtResources",
        "//submodules/Utils/RangeSet:RangeSet",
        "//submodules/InAppPurchaseManager:InAppPurchaseManager",
        "//submodules/TextFormat:TextFormat",
        "//submodules/TelegramUI/Components/AnimationCache:AnimationCache",
        "//submodules/TelegramUI/Components/MultiAnimationRenderer:MultiAnimationRenderer",
        "//submodules/TelegramCore/FlatBuffers",
        "//submodules/TelegramCore/FlatSerialization",
    ],
    visibility = [
        "//visibility:public",
    ],
)
