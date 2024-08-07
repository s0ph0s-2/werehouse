DbUtil = require("db")
FsTools = require("fstools")
local luaunit = require("third_party.luaunit")
_ = require("functools")
local pipeline = require("scraper_pipeline")
Nu = require("network_utils")
HtmlParser = require("third_party.htmlparser")
Multipart = require("third_party.multipart")
local bot = require("tg_bot")

TestFunctools = {}
function TestFunctools:testStartswithWorks()
    local s = "hello world"
    local actual1 = s:startswith("hello")
    local actual2 = s:startswith("wombat")
    luaunit.assertEquals(actual1, true)
    luaunit.assertEquals(actual2, false)
end

function TestFunctools:testEndswithWorks()
    local s = "hello world"
    local actual1 = s:endswith("world")
    local actual2 = s:endswith("wombat")
    luaunit.assertEquals(actual1, true)
    luaunit.assertEquals(actual2, false)
end

function TestFunctools:testUtf16IndexWorks()
    local s = "abc"
    luaunit.assertEquals(s:utf16index(1), 1)
    luaunit.assertEquals(s:utf16index(2), 2)
    luaunit.assertEquals(s:utf16index(3), 3)
    local complex = " · "
    luaunit.assertEquals(complex:utf16index(1), 1)
    luaunit.assertEquals(complex:utf16index(2), 2)
    luaunit.assertEquals(complex:utf16index(3), 4)
end

function TestFunctools:testUtf16SubWorks()
    local s = "abc"
    luaunit.assertEquals(s:utf16sub(2, 3), s:sub(2, 3))
    local complex = " · asdf"
    luaunit.assertEquals(complex:utf16sub(2, 3), complex:sub(2, 4))
end

function TestFunctools:testMapWorks()
    local seq = { 0, 1, 2, 3 }
    local adder = function(x)
        return x + 1
    end
    local expected = { 1, 2, 3, 4 }
    local result = table.map(seq, adder)
    luaunit.assertEquals(result, expected)
end

function TestFunctools:testFilterWorks()
    local seq = { 1, 2, 10, 40, 90, 65536 }
    local gt50 = function(x)
        return x > 50
    end
    local expected = { 90, 65536 }
    local result = table.filter(seq, gt50)
    luaunit.assertEquals(result, expected)
end

function TestFunctools:testReduceWorks()
    local seq = { "you ", "ass", "hole" }
    local cat = function(acc, next)
        return (acc or "") .. next
    end
    local expected = "you asshole"
    local result = table.reduce(seq, cat)
    luaunit.assertEquals(result, expected)
end

function TestFunctools:testFlattenWorks()
    local seq = { 0, 1, { 2, { 3, 4 } }, 5, 6 }
    local expected = { 0, 1, 2, 3, 4, 5, 6 }
    local result = table.flatten(seq)
    luaunit.assertEquals(result, expected)
end

function TestFunctools:testFlattenDoesntMangleMapTables()
    local seq = { 0, { 1, { foo = "bar" } }, 2 }
    local expected = { 0, 1, { foo = "bar" }, 2 }
    local result = table.flatten(seq)
    luaunit.assertEquals(result, expected)
end

function TestFunctools:testFlattenDoesntIntroduceGarbageOnEmptyTable()
    local seq = { { 0, 1, 2 }, {}, { 3, 4 }, { 5 }, {}, { 6, 7, 8 } }
    local expected = { 0, 1, 2, 3, 4, 5, 6, 7, 8 }
    local result = table.flatten(seq)
    luaunit.assertEquals(result, expected)
end

function TestFunctools:testFiltermapWorks()
    local seq = { 0, 1, 4, 0, 6, 10, 0 }
    local expected = { 2, 5, 7, 11 }
    local result = table.filtermap(seq, function(item)
        return item ~= 0
    end, function(item)
        return item + 1
    end)
    luaunit.assertEquals(result, expected)
end

function TestFunctools:testCollectWorks()
    local seq_good = { Ok(1), Ok(2), Ok(3), Ok(4) }
    local seq_bad = { Ok(1), Ok(2), Err("fart"), Ok(4) }
    local expected_good = Ok { 1, 2, 3, 4 }
    local expected_bad = Err("fart")
    local result_good = table.collect(seq_good)
    local result_bad = table.collect(seq_bad)
    luaunit.assertEquals(result_good, expected_good)
    luaunit.assertEquals(result_bad, expected_bad)
end

function TestFunctools:testCollectLenientWorks()
    local tests = {
        {
            input = { Ok(1), Ok(2), Ok(3), Ok(4) },
            expected = Ok { 1, 2, 3, 4 },
        },
        {
            input = { Ok(1), Ok(2), Err("fart"), Ok(4) },
            expected = Ok { 1, 2, 4 },
        },
        {
            input = { Err("fart1"), Err("fart2") },
            expected = Err("fart1"),
        },
    }
    for _, test in ipairs(tests) do
        local result = table.collect_lenient(test.input)
        luaunit.assertEquals(result, test.expected)
    end
end

function TestFunctools:testBatchWorks()
    local input = { 0, 1, 2, 3, 4, 5, 6 }
    local expected = { { 0, 1 }, { 2, 3 }, { 4, 5 }, { 6 } }
    local result = table.batch(input, 2)
    luaunit.assertEquals(result, expected)
end

function TestFunctools:testBatchWorksWhenBatchSizeSmallerThanList()
    local input = { 0 }
    local expected = { { 0 } }
    local result = table.batch(input, 2)
    luaunit.assertEquals(result, expected)
end

---@alias MockData {whenCalledWith: string, thenReturn: any[]}

---@param data MockData[]
local function fetch_mock(data)
    local orig = Fetch
    Fetch = function(url, opts)
        for _, item in ipairs(data) do
            if type(item.whenCalledWith) == "string" then
                if item.whenCalledWith == url then
                    return table.unpack(item.thenReturn)
                end
            end
        end
        Log(
            kLogWarn,
            "No mock match for URL(%s), Options(%s)" % { url, EncodeJson(opts) }
        )
    end
    return orig
end

---@param url string
---@return MockData
local function fetch_mock_head_html_200(url)
    return {
        whenCalledWith = url,
        thenReturn = {
            200,
            { ["Content-Type"] = "text/html" },
            "",
        },
    }
end

---@alias ProcessEntryTest { input: ActiveQueueEntry, expected: { 1: EntryTask, 2: ScraperError } }

---@param test_data ProcessEntryTest[]
---@param mocks MockData[]
local function process_entry_framework(test_data, mocks)
    local original = fetch_mock(mocks)
    local results = {}
    for _, test in ipairs(test_data) do
        local result, errmsg = pipeline.scrape_sources(test.input)
        table.insert(results, {
            input = test.input,
            expected = test.expected,
            output = { result, errmsg },
        })
    end
    -- Must do this before asserting so that I don't leave global state messed up
    Fetch = original
    for _, result in ipairs(results) do
        luaunit.assertEquals(
            result.output[2],
            result.expected[2],
            "error mismatch for input: %s" % { result.input }
        )
        -- Remove image data (if present) because luaunit.assertEquals chokes when the object is too large.
        if
            result.output[1]
            and result.output[1].fetch
            and result.output[1].fetch[1]
            and result.output[1].fetch[1].image_data
        then
            result.output[1].fetch[1].image_data = "elided"
        end
        luaunit.assertEquals(
            result.output[1],
            result.expected[1],
            "output mismatch for input: %s" % { result.input }
        )
    end
end

TestScraperPipeline = {}

function TestScraperPipeline:testExampleLinkPermanentFailureShouldError()
    local input = { "test://shouldFailPermanently" }
    TestScraperProcessUri = function()
        return nil, PermScraperError("404")
    end
    local original = fetch_mock {
        {
            whenCalledWith = "test://shouldFailPermanently",
            thenReturn = { 200, {}, "" },
        },
    }
    local result, error = pipeline.scrape_sources(input)
    Fetch = original
    luaunit.assertIsNil(result)
    luaunit.assertNotIsNil(error)
    ---@cast error ScraperError
    luaunit.assertEquals(error.type, 1)
end

function TestScraperPipeline:testValidBskyLinks()
    local input = {
        "https://bsky.app/profile/did:plc:4gjc5765wbtvrkdxysyvaewz/post/3kphxqgx6iv2b",
    }
    local mocks = {
        fetch_mock_head_html_200(
            "https://bsky.app/profile/did:plc:4gjc5765wbtvrkdxysyvaewz/post/3kphxqgx6iv2b"
        ),
        {
            whenCalledWith = "https://bsky.social/xrpc/com.atproto.repo.getRecord?repo=did%3Aplc%3A4gjc5765wbtvrkdxysyvaewz&collection=app.bsky.feed.post&rkey=3kphxqgx6iv2b",
            thenReturn = { 200, {}, Slurp("./test/bsky_example.json") },
        },
        {
            whenCalledWith = "https://bsky.social/xrpc/com.atproto.repo.describeRepo?repo=did%3Aplc%3A4gjc5765wbtvrkdxysyvaewz",
            thenReturn = {
                200,
                {},
                [[{"handle":"bigcozyorca.art","did":"did:plc:4gjc5765wbtvrkdxysyvaewz","didDoc":{"@context":["https://www.w3.org/ns/did/v1","https://w3id.org/security/multikey/v1","https://w3id.org/security/suites/secp256k1-2019/v1"],"id":"did:plc:4gjc5765wbtvrkdxysyvaewz","alsoKnownAs":["at://bigcozyorca.art"],"verificationMethod":[{"id":"did:plc:4gjc5765wbtvrkdxysyvaewz#atproto","type":"Multikey","controller":"did:plc:4gjc5765wbtvrkdxysyvaewz","publicKeyMultibase":"zQ3shk8eMicPrTviAy8AFU1YDTg4Y1Vcx6KL8kScPuqn9YPhX"}],"service":[{"id":"#atproto_pds","type":"AtprotoPersonalDataServer","serviceEndpoint":"https://puffball.us-east.host.bsky.network"}]},"collections":["app.bsky.actor.profile","app.bsky.feed.like","app.bsky.feed.post","app.bsky.feed.repost","app.bsky.graph.block","app.bsky.graph.follow"],"handleIsCorrect":true}]],
            },
        },
        {
            whenCalledWith = "https://bsky.social/xrpc/com.atproto.repo.listRecords?repo=did%3Aplc%3A4gjc5765wbtvrkdxysyvaewz&collection=app.bsky.actor.profile&limit=1",
            thenReturn = {
                200,
                {},
                [[{"records":[{"uri":"at://did:plc:4gjc5765wbtvrkdxysyvaewz/app.bsky.actor.profile/self","cid":"bafyreidyznavjmovmun7bgixgxjz3zu24j7jjaj23fr5allx4pbusbn6ei","value":{"$type":"app.bsky.actor.profile","avatar":{"$type":"blob","ref":{"$link":"bafkreiabtb4hbusnizey2sqzdtdy5fza72e5d5alovjpn6hvkolvozegwa"},"mimeType":"image/jpeg","size":905826},"banner":{"$type":"blob","ref":{"$link":"bafkreibiet6367gxfkhj3ua5vdgdbbvubucpkxbyekssgngi3zcww7ukia"},"mimeType":"image/jpeg","size":362391},"description":"He/They\n18+ (NO MINORS)\nA 🔞NSFW furry artist!!\nTrying out new platforms to spread out.","displayName":"BigCozyOrca 🔞"}}],"cursor":"self"}]],
            },
        },
    }
    local expected = {
        fetch = table.map({
            "https://bsky.social/xrpc/com.atproto.sync.getBlob?did=did%3Aplc%3A4gjc5765wbtvrkdxysyvaewz&cid=bafkreib2v6upf5gz7q22jpdnrh2fwhtn6yexrsnbp6uh7ythgq3obhf7ia",
            "https://bsky.social/xrpc/com.atproto.sync.getBlob?did=did%3Aplc%3A4gjc5765wbtvrkdxysyvaewz&cid=bafkreidjkqudkq2m6pojavuelcud2fez2eojxiflnxedimplumiygu76pe",
        }, function(item)
            return {
                authors = {
                    {
                        display_name = "BigCozyOrca 🔞",
                        handle = "bigcozyorca.art",
                        profile_url = "https://bsky.app/profile/did:plc:4gjc5765wbtvrkdxysyvaewz",
                    },
                },
                canonical_domain = "bsky.app",
                height = 2000,
                mime_type = "image/jpeg",
                this_source = "https://bsky.app/profile/did:plc:4gjc5765wbtvrkdxysyvaewz/post/3kphxqgx6iv2b",
                raw_image_uri = item,
                width = 1905,
                kind = DbUtil.k.ImageKind.Image,
            }
        end),
    }
    local tests = {
        { input = input, expected = { expected, nil } },
    }
    process_entry_framework(tests, mocks)
end

function TestScraperPipeline:testBskyLinkWithNoAspectRatio()
    local input = {
        "https://bsky.app/profile/did:plc:bkq6i3w4hg7zkzuf5phyfdxg/post/3kb4ebxmabw2v",
    }
    local mocks = {
        fetch_mock_head_html_200(
            "https://bsky.app/profile/did:plc:bkq6i3w4hg7zkzuf5phyfdxg/post/3kb4ebxmabw2v"
        ),
        {
            whenCalledWith = "https://bsky.social/xrpc/com.atproto.repo.getRecord?repo=did%3Aplc%3Abkq6i3w4hg7zkzuf5phyfdxg&collection=app.bsky.feed.post&rkey=3kb4ebxmabw2v",
            thenReturn = { 200, {}, Slurp("./test/bsky_no_aspectratio.json") },
        },
        {
            whenCalledWith = "https://bsky.social/xrpc/com.atproto.repo.describeRepo?repo=did%3Aplc%3Abkq6i3w4hg7zkzuf5phyfdxg",
            thenReturn = {
                200,
                {},
                [[{"handle":"bigcozyorca.art","did":"did:plc:4gjc5765wbtvrkdxysyvaewz","didDoc":{"@context":["https://www.w3.org/ns/did/v1","https://w3id.org/security/multikey/v1","https://w3id.org/security/suites/secp256k1-2019/v1"],"id":"did:plc:4gjc5765wbtvrkdxysyvaewz","alsoKnownAs":["at://bigcozyorca.art"],"verificationMethod":[{"id":"did:plc:4gjc5765wbtvrkdxysyvaewz#atproto","type":"Multikey","controller":"did:plc:4gjc5765wbtvrkdxysyvaewz","publicKeyMultibase":"zQ3shk8eMicPrTviAy8AFU1YDTg4Y1Vcx6KL8kScPuqn9YPhX"}],"service":[{"id":"#atproto_pds","type":"AtprotoPersonalDataServer","serviceEndpoint":"https://puffball.us-east.host.bsky.network"}]},"collections":["app.bsky.actor.profile","app.bsky.feed.like","app.bsky.feed.post","app.bsky.feed.repost","app.bsky.graph.block","app.bsky.graph.follow"],"handleIsCorrect":true}]],
            },
        },
        {
            whenCalledWith = "https://bsky.social/xrpc/com.atproto.repo.listRecords?repo=did%3Aplc%3Abkq6i3w4hg7zkzuf5phyfdxg&collection=app.bsky.actor.profile&limit=1",
            thenReturn = {
                200,
                {},
                [[{"records":[{"uri":"at://did:plc:4gjc5765wbtvrkdxysyvaewz/app.bsky.actor.profile/self","cid":"bafyreidyznavjmovmun7bgixgxjz3zu24j7jjaj23fr5allx4pbusbn6ei","value":{"$type":"app.bsky.actor.profile","avatar":{"$type":"blob","ref":{"$link":"bafkreiabtb4hbusnizey2sqzdtdy5fza72e5d5alovjpn6hvkolvozegwa"},"mimeType":"image/jpeg","size":905826},"banner":{"$type":"blob","ref":{"$link":"bafkreibiet6367gxfkhj3ua5vdgdbbvubucpkxbyekssgngi3zcww7ukia"},"mimeType":"image/jpeg","size":362391},"description":"He/They\n18+ (NO MINORS)\nA 🔞NSFW furry artist!!\nTrying out new platforms to spread out.","displayName":"BigCozyOrca 🔞"}}],"cursor":"self"}]],
            },
        },
    }
    local expected = {
        fetch = table.map({
            "https://bsky.social/xrpc/com.atproto.sync.getBlob?did=did%3Aplc%3Abkq6i3w4hg7zkzuf5phyfdxg&cid=bafkreie4pcim2xsuzgjstzhprtkfjiam2vqlgygjhxujiduvoxs5z2opr4",
            "https://bsky.social/xrpc/com.atproto.sync.getBlob?did=did%3Aplc%3Abkq6i3w4hg7zkzuf5phyfdxg&cid=bafkreiag6auhhw5by6nrkmgzzhtxetqtmsa55o3o7rnyzwhohxga3cfpoq",
            "https://bsky.social/xrpc/com.atproto.sync.getBlob?did=did%3Aplc%3Abkq6i3w4hg7zkzuf5phyfdxg&cid=bafkreibxygqam6gddpcexktzuup6js52g2fx73ytip3ptdetc4d6g3kq4u",
        }, function(item)
            return {
                authors = {
                    {
                        display_name = "BigCozyOrca 🔞",
                        handle = "bigcozyorca.art",
                        profile_url = "https://bsky.app/profile/did:plc:bkq6i3w4hg7zkzuf5phyfdxg",
                    },
                },
                canonical_domain = "bsky.app",
                height = 0,
                mime_type = "image/jpeg",
                this_source = "https://bsky.app/profile/did:plc:bkq6i3w4hg7zkzuf5phyfdxg/post/3kb4ebxmabw2v",
                raw_image_uri = item,
                width = 0,
                kind = DbUtil.k.ImageKind.Image,
            }
        end),
    }
    local tests = {
        { input = input, expected = { expected, nil } },
    }
    process_entry_framework(tests, mocks)
end

function TestScraperPipeline:testValidTwitterLinks()
    local tweetTrackingParams =
        "https://twitter.com/thatFunkybun/status/1778885919572979806?s=19"
    local tweetVxtwitter =
        "https://vxtwitter.com/thatFunkybun/status/1778885919572979806"
    local tweetNitter =
        "https://nitter.privacydev.net/thatFunkybun/status/1778885919572979806#m"
    local tweetGif =
        "https://twitter.com/bigcozyorca/status/1793851828477788591"
    local tweetVideo =
        "https://twitter.com/Danamasco/status/1791127158523314321"
    local tweetPhoto1 =
        "https://vxtwitter.com/JackieTheYeen/status/1810173812761383143/photo/1"
    local mocks = {
        fetch_mock_head_html_200(tweetTrackingParams),
        fetch_mock_head_html_200(tweetVxtwitter),
        fetch_mock_head_html_200(tweetNitter),
        fetch_mock_head_html_200(tweetGif),
        fetch_mock_head_html_200(tweetVideo),
        fetch_mock_head_html_200(tweetPhoto1),
        {
            whenCalledWith = "https://api.fxtwitter.com/status/1778885919572979806",
            thenReturn = {
                200,
                {},
                Slurp("test/twitter_fxtwitter_response.json"),
            },
        },
        {
            whenCalledWith = "https://api.fxtwitter.com/status/1793851828477788591",
            thenReturn = {
                200,
                {},
                Slurp("test/twitter_fxtwitter_gif_response.json"),
            },
        },
        {
            whenCalledWith = "https://api.fxtwitter.com/status/1791127158523314321",
            thenReturn = {
                200,
                {},
                Slurp("test/twitter_fxtwitter_video_response.json"),
            },
        },
        {
            whenCalledWith = "https://api.fxtwitter.com/status/1810173812761383143",
            thenReturn = {
                200,
                {},
                Slurp("test/twitter_fxtwitter_photo1_response.json"),
            },
        },
    }
    local authorImage = {
        handle = "thatFunkybun",
        display_name = "Funkybun",
        profile_url = "https://twitter.com/thatFunkybun",
    }
    local authorGif = {
        handle = "bigcozyorca",
        display_name = "BigCozyOrca💫🔞",
        profile_url = "https://twitter.com/bigcozyorca",
    }
    local authorVideo = {
        handle = "Danamasco",
        display_name = "Danamasco",
        profile_url = "https://twitter.com/Danamasco",
    }
    local authorPhoto1 = {
        handle = "JackieTheYeen",
        display_name = "Jackie the Yeen",
        profile_url = "https://twitter.com/JackieTheYeen",
    }
    local expectedImage = {
        fetch = table.map({
            "https://pbs.twimg.com/media/GK_fDarXQAE6yBj.jpg",
            "https://pbs.twimg.com/media/GK_fDaaXsAATM_X.jpg",
            "https://pbs.twimg.com/media/GK_fDaUWYAABb40.jpg",
            "https://pbs.twimg.com/media/GK_fDaUXsAAGJng.jpg",
        }, function(item)
            return {
                kind = DbUtil.k.ImageKind.Image,
                this_source = "https://twitter.com/thatFunkybun/status/1778885919572979806",
                canonical_domain = "twitter.com",
                height = 2300,
                mime_type = "image/jpeg",
                raw_image_uri = item,
                width = 1600,
                authors = { authorImage },
                rating = DbUtil.k.Rating.Adult,
            }
        end),
    }
    local expectedGif = {
        fetch = {
            {
                kind = DbUtil.k.ImageKind.Animation,
                this_source = "https://twitter.com/bigcozyorca/status/1793851828477788591",
                canonical_domain = "twitter.com",
                height = 492,
                width = 636,
                mime_type = "video/mp4",
                raw_image_uri = "https://video.twimg.com/tweet_video/GOUJuRLWwAA151Q.mp4",
                authors = { authorGif },
                thumbnails = {
                    {
                        height = 492,
                        raw_uri = "https://pbs.twimg.com/tweet_video_thumb/GOUJuRLWwAA151Q.jpg",
                        scale = 1,
                        width = 636,
                    },
                },
                rating = DbUtil.k.Rating.General,
            },
        },
    }
    local expectedVideo = {
        fetch = {
            {
                kind = DbUtil.k.ImageKind.Video,
                this_source = "https://twitter.com/Danamasco/status/1791127158523314321",
                canonical_domain = "twitter.com",
                height = 720,
                width = 1280,
                mime_type = "video/mp4",
                raw_image_uri = "https://video.twimg.com/ext_tw_video/1791127090936389632/pu/vid/avc1/1280x720/AdLRmgf0MmgEDk3V.mp4?tag=12",
                authors = { authorVideo },
                thumbnails = {
                    {
                        height = 720,
                        raw_uri = "https://pbs.twimg.com/ext_tw_video_thumb/1791127090936389632/pu/img/m2R9ChNWPO630fkA.jpg",
                        scale = 1,
                        width = 1280,
                    },
                },
                rating = DbUtil.k.Rating.General,
            },
        },
    }
    local expectedPhoto1 = {
        fetch = {
            {
                kind = DbUtil.k.ImageKind.Image,
                authors = { authorPhoto1 },
                canonical_domain = "twitter.com",
                height = 1200,
                kind = DbUtil.k.ImageKind.Image,
                mime_type = "image/jpeg",
                rating = DbUtil.k.Rating.General,
                raw_image_uri = "https://pbs.twimg.com/media/GR8GzykbkAACRqi.jpg",
                this_source = "https://twitter.com/JackieTheYeen/status/1810173812761383143",
                width = 1200,
            },
        },
    }
    local tests = {
        {
            input = { tweetTrackingParams },
            expected = { expectedImage, nil },
        },
        {
            input = { tweetVxtwitter },
            expected = { expectedImage, nil },
        },
        {
            input = { tweetNitter },
            expected = { expectedImage, nil },
        },
        {
            input = { tweetGif },
            expected = { expectedGif, nil },
        },
        {
            input = { tweetVideo },
            expected = { expectedVideo, nil },
        },
        {
            input = { tweetPhoto1 },
            expected = { expectedPhoto1, nil },
        },
    }
    process_entry_framework(tests, mocks)
end

function TestScraperPipeline:testValidFuraffinityLinks()
    local inputRegular = "https://www.furaffinity.net/view/36328438"
    local regularWithFull = "https://www.furaffinity.net/full/36328438"
    local inputFx = "https://www.fxfuraffinity.net/view/36328438"
    local inputX = "https://www.xfuraffinity.net/view/36328438"
    local inputNoWwwFull = "https://furaffinity.net/full/36328438"
    local mocks = {
        fetch_mock_head_html_200(inputRegular),
        fetch_mock_head_html_200(inputFx),
        fetch_mock_head_html_200(inputX),
        fetch_mock_head_html_200(inputNoWwwFull),
        {
            whenCalledWith = regularWithFull,
            thenReturn = { 200, {}, Slurp("test/fa_example.html") },
        },
    }
    local expected = {
        fetch = {
            {
                kind = DbUtil.k.ImageKind.Image,
                authors = {
                    {
                        handle = "Glopossum",
                        display_name = "Glopossum",
                        profile_url = "https://www.furaffinity.net/user/glopossum/",
                    },
                },
                canonical_domain = "www.furaffinity.net",
                height = 1280,
                mime_type = "image/png",
                raw_image_uri = "https://d.furaffinity.net/art/glopossum/1589320262/1589320262.glopossum_chloelatex.png",
                this_source = regularWithFull,
                width = 960,
                rating = DbUtil.k.Rating.Adult,
                incoming_tags = {
                    "dragon",
                    "reptile",
                    "scalie",
                    "latex",
                    "catsuit",
                    "full",
                    "body",
                    "collar",
                    "peace",
                    "sign",
                    "trans",
                    "transgender",
                    "her",
                    "being",
                    "into",
                    "latex",
                    "is",
                    "character",
                    "development",
                    "right",
                },
            },
        },
    }
    local tests = {
        {
            input = { inputRegular },
            expected = { expected, nil },
        },
        {
            input = { inputFx },
            expected = { expected, nil },
        },
        {
            input = { inputX },
            expected = { expected, nil },
        },
        {
            input = { inputNoWwwFull },
            expected = { expected, nil },
        },
    }
    process_entry_framework(tests, mocks)
end

function TestScraperPipeline:testValidE6Links()
    local inputRegular = "https://e621.net/posts/4366241"
    local inputQueryParams =
        "https://e621.net/posts/4366241?q=filetype%3Ajpg+order%3Ascore"
    local inputQueryParamsWithJson =
        "https://e621.net/posts/4366241.json?q=filetype%3Ajpg%2Border%3Ascore"
    local inputThirdPartyEdit = "https://e621.net/posts/4721029"
    local inputPool = "https://e621.net/pools/40574"
    local expectedRegular = {
        fetch = {
            {
                kind = DbUtil.k.ImageKind.Image,
                canonical_domain = "e621.net",
                height = 1100,
                mime_type = "image/jpeg",
                raw_image_uri = "https://static1.e621.net/data/63/f2/63f28a75d91d42252326235a03efe93e.jpg",
                this_source = inputRegular,
                additional_sources = {
                    "https://twitter.com/BeaganBong/status/1715891189566881976",
                    "https://pbs.twimg.com/media/F9AR0lUagAAq1wc?format=jpg&name=orig",
                },
                width = 880,
                rating = DbUtil.k.Rating.Explicit,
                authors = {
                    {
                        display_name = "reagan_long",
                        handle = "reagan_long",
                        profile_url = "https://e621.net/posts?tags=reagan_long",
                    },
                },
                thumbnails = {
                    {
                        height = 150,
                        raw_uri = "https://static1.e621.net/data/preview/63/f2/63f28a75d91d42252326235a03efe93e.jpg",
                        scale = 1,
                        width = 120,
                    },
                },
                incoming_tags = {
                    "anal_beads",
                    "animal_dildo",
                    "animal_genitalia",
                    "animal_penis",
                    "animal_sex_toy",
                    "anthro",
                    "anus",
                    "areola",
                    "backsack",
                    "balls",
                    "big_anus",
                    "big_balls",
                    "big_penis",
                    "black_anus",
                    "black_balls",
                    "black_perineum",
                    "blue_body",
                    "bodily_fluids",
                    "breasts",
                    "butt",
                    "canine_genitalia",
                    "canine_penis",
                    "caught",
                    "chest_spike",
                    "cjk_tally_marks",
                    "condom",
                    "dialogue",
                    "dildo",
                    "equine_dildo",
                    "gag",
                    "genitals",
                    "gynomorph",
                    "huge_penis",
                    "hyper",
                    "hyper_genitalia",
                    "hyper_penis",
                    "intersex",
                    "knot",
                    "locker",
                    "looking_at_viewer",
                    "looking_back",
                    "looking_back_at_viewer",
                    "master",
                    "nipples",
                    "nude",
                    "nude_anthro",
                    "nude_gynomorph",
                    "nude_intersex",
                    "open_mouth",
                    "penis",
                    "perineum",
                    "photo",
                    "pink_penis",
                    "presenting",
                    "presenting_anus",
                    "presenting_hindquarters",
                    "puffy_anus",
                    "red_eyes",
                    "sex_toy",
                    "sexual_barrier_device",
                    "solo",
                    "spikes",
                    "spikes_(anatomy)",
                    "sweat",
                    "sweaty_anus",
                    "sweaty_balls",
                    "sweaty_butt",
                    "sweaty_genitalia",
                    "tail",
                    "tally_marks",
                    "text",
                    "nintendo",
                    "pokemon",
                    "gardevoir",
                    "generation_3_pokemon",
                    "generation_4_pokemon",
                    "lucario",
                    "pokemon_(species)",
                    "4:5",
                    "digital_media_(artwork)",
                    "english_text",
                    "url",
                },
            },
        },
    }
    local expectedPool = {
        fetch = {
            {
                kind = DbUtil.k.ImageKind.Image,
                additional_sources = {
                    "https://www.furaffinity.net/view/56522599",
                    "https://e621.net/pools/40574",
                },
                authors = {
                    {
                        display_name = "64k",
                        handle = "64k",
                        profile_url = "https://e621.net/posts?tags=64k",
                    },
                },
                canonical_domain = "e621.net",
                height = 3456,
                mime_type = "image/jpeg",
                raw_image_uri = "https://static1.e621.net/data/15/1a/151a1af93e572cdf611f919e975c8268.jpg",
                this_source = "https://e621.net/posts/4763407",
                width = 4152,
                rating = DbUtil.k.Rating.Explicit,
                thumbnails = {
                    {
                        height = 124,
                        raw_uri = "https://static1.e621.net/data/preview/15/1a/151a1af93e572cdf611f919e975c8268.jpg",
                        scale = 1,
                        width = 150,
                    },
                },
                incoming_tags = {
                    "animal_genitalia",
                    "anus",
                    "big_butt",
                    "black_body",
                    "black_fur",
                    "black_hair",
                    "butt",
                    "claws",
                    "dialogue",
                    "eyebrows",
                    "fangs",
                    "feral",
                    "fluffy",
                    "fluffy_tail",
                    "fur",
                    "genitals",
                    "hair",
                    "hair_mane",
                    "hair_over_eye",
                    "male",
                    "neck_tuft",
                    "one_eye_obstructed",
                    "pawpads",
                    "pink_pawpads",
                    "pokeball",
                    "presenting",
                    "presenting_anus",
                    "presenting_hindquarters",
                    "puffy_anus",
                    "sheath",
                    "smile",
                    "solo",
                    "tail",
                    "talking_to_viewer",
                    "teeth",
                    "text",
                    "tuft",
                    "white_body",
                    "white_fur",
                    "nintendo",
                    "pokemon",
                    "canid",
                    "canine",
                    "generation_3_pokemon",
                    "mammal",
                    "mightyena",
                    "pokemon_(species)",
                    "absurd_res",
                    "english_text",
                    "hi_res",
                },
            },
            {
                kind = DbUtil.k.ImageKind.Image,
                additional_sources = {
                    "https://www.furaffinity.net/view/56529598",
                    "https://e621.net/pools/40574",
                },
                authors = {
                    {
                        display_name = "64k",
                        handle = "64k",
                        profile_url = "https://e621.net/posts?tags=64k",
                    },
                },
                canonical_domain = "e621.net",
                height = 3144,
                mime_type = "image/jpeg",
                raw_image_uri = "https://static1.e621.net/data/b0/e4/b0e4f3473858c235c21cde98336a10bd.jpg",
                this_source = "https://e621.net/posts/4764946",
                width = 3648,
                rating = DbUtil.k.Rating.Explicit,
                thumbnails = {
                    {
                        height = 129,
                        raw_uri = "https://static1.e621.net/data/preview/b0/e4/b0e4f3473858c235c21cde98336a10bd.jpg",
                        scale = 1,
                        width = 150,
                    },
                },
                incoming_tags = {
                    "animal_genitalia",
                    "anus",
                    "big_butt",
                    "black_body",
                    "black_fur",
                    "black_hair",
                    "butt",
                    "close-up",
                    "dialogue",
                    "eyebrows",
                    "fangs",
                    "feral",
                    "fluffy",
                    "fluffy_tail",
                    "fur",
                    "genitals",
                    "hair",
                    "hair_mane",
                    "hair_over_eye",
                    "looking_back",
                    "male",
                    "neck_tuft",
                    "one_eye_obstructed",
                    "presenting",
                    "presenting_anus",
                    "presenting_hindquarters",
                    "puffy_anus",
                    "solo",
                    "tail",
                    "talking_to_viewer",
                    "teasing",
                    "teasing_viewer",
                    "teeth",
                    "text",
                    "tuft",
                    "white_body",
                    "white_fur",
                    "nintendo",
                    "pokemon",
                    "canid",
                    "canine",
                    "generation_3_pokemon",
                    "mammal",
                    "mightyena",
                    "pokemon_(species)",
                    "absurd_res",
                    "english_text",
                    "hi_res",
                },
            },
        },
    }
    local inputVideo = "https://e621.net/posts/2848682"
    local inputGif = "https://e621.net/posts/3105830"
    local tests = {
        {
            input = { inputRegular },
            expected = { expectedRegular, nil },
        },
        {
            input = { inputQueryParams },
            expected = { expectedRegular, nil },
        },
        {
            input = { inputVideo },
            expected = {
                {
                    fetch = {
                        {
                            additional_sources = {
                                "https://www.zonkpunch.wtf/",
                                "https://www.patreon.com/zonkpunch",
                            },
                            authors = {
                                {
                                    display_name = "zonkpunch",
                                    handle = "zonkpunch",
                                    profile_url = "https://e621.net/posts?tags=zonkpunch",
                                },
                            },
                            canonical_domain = "e621.net",
                            height = 640,
                            incoming_tags = {
                                "3_toes",
                                "4_toes",
                                "5_fingers",
                                "abs",
                                "against_surface",
                                "against_wall",
                                "ahegao",
                                "airlock",
                                "all_fours",
                                "anal",
                                "anal_orgasm",
                                "anal_penetration",
                                "anal_tugging",
                                "anal_wink",
                                "animal_genitalia",
                                "anthro",
                                "anthro_on_anthro",
                                "anthro_on_bottom",
                                "anthro_on_top",
                                "anthro_penetrated",
                                "anthro_penetrating",
                                "anthro_penetrating_anthro",
                                "anthro_pov",
                                "anus",
                                "aroused",
                                "audible_creampie",
                                "audible_throbbing",
                                "backsack",
                                "ball_size_difference",
                                "ball_slap",
                                "ball_squish",
                                "balls",
                                "balls_blush",
                                "balls_deep",
                                "balls_on_face",
                                "balls_on_glass",
                                "balls_shot",
                                "balls_touching",
                                "bareback",
                                "becoming_erect",
                                "belly",
                                "belly_inflation",
                                "biceps",
                                "big_balls",
                                "big_belly",
                                "big_butt",
                                "big_dom_small_sub",
                                "big_penis",
                                "biped",
                                "bite",
                                "biting_lip",
                                "biting_own_lip",
                                "black_nose",
                                "blue_body",
                                "blue_eyes",
                                "blue_skin",
                                "blush",
                                "bodily_fluids",
                                "body_blush",
                                "body_part_in_ass",
                                "body_part_in_mouth",
                                "bouncing_balls",
                                "bouncing_penis",
                                "breath",
                                "brown_body",
                                "brown_fur",
                                "butt",
                                "butt_focus",
                                "carrying_another",
                                "cheek_tuft",
                                "chest_tuft",
                                "chromatic_aberration",
                                "claws",
                                "clenched_teeth",
                                "close-up",
                                "cloud",
                                "cock_hanging",
                                "countershading",
                                "crotch_shot",
                                "crotch_sniffing",
                                "cum",
                                "cum_covered",
                                "cum_drip",
                                "cum_expulsion",
                                "cum_from_ass",
                                "cum_from_mouth",
                                "cum_in_ass",
                                "cum_in_mouth",
                                "cum_inflation",
                                "cum_inside",
                                "cum_on_balls",
                                "cum_on_face",
                                "cum_on_penis",
                                "cum_on_viewer",
                                "cum_pool",
                                "cum_splatter",
                                "cum_while_penetrated",
                                "cumming_at_viewer",
                                "cumshot",
                                "cumshot_on_face",
                                "curling_toes",
                                "cute_fangs",
                                "deep_penetration",
                                "deep_throat",
                                "deltoids",
                                "detailed_background",
                                "dominant",
                                "dominant_anthro",
                                "dominant_male",
                                "drinking",
                                "drinking_cum",
                                "dripping",
                                "drooling",
                                "duo",
                                "echo",
                                "ejaculation",
                                "erection",
                                "excessive_cum",
                                "excessive_genital_fluids",
                                "eye_contact",
                                "eye_roll",
                                "eyes_closed",
                                "face_fucking",
                                "facial_tuft",
                                "fangs",
                                "feet",
                                "fellatio",
                                "fellatio_pov",
                                "fingers",
                                "first_person_view",
                                "flaccid",
                                "foreskin",
                                "frenulum",
                                "frenulum_lick",
                                "from_behind_position",
                                "front_view",
                                "fucked_silly",
                                "full_nelson",
                                "full_nelson_(legs_held)",
                                "full_nelson_position",
                                "fur",
                                "gagging",
                                "genital_fluids",
                                "genital_focus",
                                "genitals",
                                "glans",
                                "glowing",
                                "glowing_eyes",
                                "grey_balls",
                                "grey_body",
                                "grey_claws",
                                "grey_fur",
                                "grey_perineum",
                                "grey_sheath",
                                "grin",
                                "grunting",
                                "half-closed_eyes",
                                "hand_on_hip",
                                "hands-free",
                                "head_in_crotch",
                                "heartbeat",
                                "high-angle_view",
                                "hindpaw",
                                "holding_by_tail",
                                "humanoid_genitalia",
                                "humanoid_hands",
                                "humanoid_penis",
                                "hybrid_genitalia",
                                "hybrid_penis",
                                "inflation",
                                "inside",
                                "internal",
                                "internal_anal",
                                "interspecies",
                                "irrumatio",
                                "kneeling",
                                "knot",
                                "knotted_humanoid_penis",
                                "large_penetration",
                                "larger_anthro",
                                "larger_male",
                                "legs_up",
                                "licking",
                                "licking_tip",
                                "long_foreskin",
                                "long_orgasm",
                                "looking_at_another",
                                "looking_at_genitalia",
                                "looking_at_partner",
                                "looking_at_penis",
                                "looking_at_viewer",
                                "looking_pleasured",
                                "low-angle_view",
                                "male",
                                "male/male",
                                "male_on_bottom",
                                "male_on_top",
                                "male_penetrated",
                                "male_penetrating",
                                "male_penetrating_male",
                                "male_pov",
                                "messy",
                                "moan",
                                "mountain",
                                "moving_foreskin",
                                "multicolored_body",
                                "multicolored_fur",
                                "multicolored_skin",
                                "multiple_angles",
                                "multiple_orgasms",
                                "multiple_positions",
                                "musclegut",
                                "muscular",
                                "muscular_anthro",
                                "muscular_male",
                                "music",
                                "musk",
                                "musk_clouds",
                                "narrowed_eyes",
                                "navel",
                                "neck_tuft",
                                "nipples",
                                "nubbed_penis",
                                "nude",
                                "nude_anthro",
                                "nude_male",
                                "obliques",
                                "on_bottom",
                                "on_glass",
                                "on_top",
                                "open_mouth",
                                "oral",
                                "oral_penetration",
                                "orgasm",
                                "orgasm_face",
                                "panting",
                                "pawpads",
                                "paws",
                                "pecs",
                                "penetrating_pov",
                                "penetration",
                                "penile",
                                "penile_penetration",
                                "penis",
                                "penis_focus",
                                "penis_in_ass",
                                "penis_in_mouth",
                                "penis_lick",
                                "penis_shot",
                                "penis_size_difference",
                                "penis_sniffing",
                                "penis_tip",
                                "penis_towards_viewer",
                                "penis_worship",
                                "perineum",
                                "pink_anus",
                                "pink_glans",
                                "pink_pawpads",
                                "pink_penis",
                                "precum",
                                "precum_drip",
                                "presenting",
                                "presenting_penis",
                                "puffy_anus",
                                "pupils",
                                "rear_view",
                                "receiving_pov",
                                "reddened_butt",
                                "retracted_balls",
                                "retracted_foreskin",
                                "retracting_foreskin",
                                "reverse_stand_and_carry_position",
                                "ridiculous_fit",
                                "rough_sex",
                                "saggy_balls",
                                "saliva",
                                "saliva_on_penis",
                                "saliva_on_tongue",
                                "saliva_string",
                                "self_bite",
                                "sex",
                                "sharp_teeth",
                                "sheath",
                                "sitting",
                                "size_difference",
                                "slap",
                                "slightly_chubby",
                                "slit_pupils",
                                "smaller_anthro",
                                "smaller_male",
                                "smaller_penetrated",
                                "smile",
                                "smug",
                                "sniffing",
                                "soles",
                                "spread_legs",
                                "spreading",
                                "squish",
                                "standing",
                                "standing_sex",
                                "steam",
                                "submissive",
                                "submissive_anthro",
                                "submissive_male",
                                "submissive_pov",
                                "sweat",
                                "sweaty_balls",
                                "sweaty_genitalia",
                                "sweaty_penis",
                                "symbol",
                                "tail",
                                "tail_grab",
                                "tail_motion",
                                "tail_pull",
                                "tailwag",
                                "tan_balls",
                                "tan_body",
                                "tan_fur",
                                "tan_penis",
                                "tan_perineum",
                                "tan_skin",
                                "tea_bagging",
                                "teeth",
                                "text",
                                "these_aren't_my_glasses",
                                "thick_penis",
                                "thick_tail",
                                "thick_thighs",
                                "throat_swabbing",
                                "throbbing",
                                "throbbing_balls",
                                "throbbing_knot",
                                "throbbing_penis",
                                "thrusting",
                                "tight_fit",
                                "toe_claws",
                                "toes",
                                "tongue",
                                "tongue_out",
                                "triceps",
                                "tuft",
                                "two_tone_body",
                                "two_tone_fur",
                                "two_tone_skin",
                                "underpaw",
                                "unretracted_foreskin",
                                "unsheathing",
                                "urethra",
                                "vein",
                                "veiny_balls",
                                "veiny_knot",
                                "veiny_penis",
                                "warning_symbol",
                                "worm's-eye_view",
                                "yellow_eyes",
                                "mythology",
                                "kuno_bloodclaw",
                                "roshi_(sgtroshi)",
                                "canid",
                                "canine",
                                "canis",
                                "domestic_dog",
                                "dragon",
                                "mammal",
                                "mythological_creature",
                                "mythological_scalie",
                                "reptile",
                                "scalie",
                                "wingless_dragon",
                                "2021",
                                "2d_animation",
                                "animated",
                                "colored",
                                "digital_media_(artwork)",
                                "english_text",
                                "frame_by_frame",
                                "german_text",
                                "huge_filesize",
                                "long_playtime",
                                "meme",
                                "signature",
                                "sound",
                                "tag_panic",
                                "url",
                                "voice_acted",
                                "webm",
                            },
                            kind = 2,
                            mime_type = "video/webm",
                            rating = 3,
                            raw_image_uri = "https://static1.e621.net/data/06/19/0619ff5a8270aed7b22ca3981b783224.webm",
                            this_source = "https://e621.net/posts/2848682",
                            width = 1138,
                            thumbnails = {
                                {
                                    height = 84,
                                    raw_uri = "https://static1.e621.net/data/preview/06/19/0619ff5a8270aed7b22ca3981b783224.jpg",
                                    scale = 1,
                                    width = 150,
                                },
                            },
                        },
                    },
                },
                nil,
            },
        },
        {
            input = { inputGif },
            expected = {
                {
                    fetch = {
                        {
                            kind = DbUtil.k.ImageKind.Image,
                            canonical_domain = "e621.net",
                            height = 1920,
                            mime_type = "image/gif",
                            this_source = inputGif,
                            additional_sources = {
                                "https://twitter.com/its_a_mok/status/1478372140542042114",
                            },
                            raw_image_uri = "https://static1.e621.net/data/f6/d9/f6d9af24b4a47fd324bd41ebe21aeb42.gif",
                            width = 1080,
                            authors = {
                                {
                                    handle = "its_a_mok",
                                    display_name = "its_a_mok",
                                    profile_url = "https://e621.net/posts?tags=its_a_mok",
                                },
                            },
                            rating = DbUtil.k.Rating.Explicit,
                            thumbnails = {
                                {
                                    height = 150,
                                    raw_uri = "https://static1.e621.net/data/preview/f6/d9/f6d9af24b4a47fd324bd41ebe21aeb42.jpg",
                                    scale = 1,
                                    width = 84,
                                },
                            },
                            incoming_tags = {
                                "4_fingers",
                                "anthro",
                                "anus",
                                "bed",
                                "bodily_fluids",
                                "bottomwear",
                                "breasts",
                                "butt",
                                "choker",
                                "clothed",
                                "clothing",
                                "clothing_lift",
                                "collar",
                                "eyebrow_piercing",
                                "eyebrow_ring",
                                "facial_piercing",
                                "female",
                                "female_anthro",
                                "fingers",
                                "flashing",
                                "fur",
                                "furniture",
                                "genital_fluids",
                                "genitals",
                                "gloves",
                                "hair",
                                "handwear",
                                "innie_pussy",
                                "inside",
                                "jewelry",
                                "legwear",
                                "looking_at_viewer",
                                "necklace",
                                "no_underwear",
                                "piercing",
                                "presenting",
                                "presenting_anus",
                                "presenting_hindquarters",
                                "presenting_pussy",
                                "pussy",
                                "ring_piercing",
                                "rotoscoping",
                                "shaking_butt",
                                "skirt",
                                "skirt_lift",
                                "solo",
                                "spread_butt",
                                "spread_pussy",
                                "spreading",
                                "stockings",
                                "tail_under_skirt",
                                "vaginal_fluids",
                                "white_hair",
                                "helluva_boss",
                                "mythology",
                                "loona_(helluva_boss)",
                                "canid",
                                "canid_demon",
                                "canine",
                                "demon",
                                "hellhound",
                                "mammal",
                                "mythological_canine",
                                "mythological_creature",
                                "9:16",
                                "animated",
                                "hi_res",
                                "short_playtime",
                            },
                        },
                    },
                },
                nil,
            },
        },
        {
            input = { inputThirdPartyEdit },
            expected = {
                {
                    fetch = {
                        {
                            kind = DbUtil.k.ImageKind.Image,
                            canonical_domain = "e621.net",
                            height = 2103,
                            mime_type = "image/jpeg",
                            this_source = inputThirdPartyEdit,
                            additional_sources = {
                                "https://www.furaffinity.net/view/56276968/",
                                "https://itaku.ee/images/806865",
                                "https://www.weasyl.com/~kuruk/submissions/2369253/trying-out-the-vixenmaker-pt-3-color",
                                "https://inkbunny.net/s/3299951",
                            },
                            raw_image_uri = "https://static1.e621.net/data/dc/90/dc90a909c40a2c602143dbf765c2074f.jpg",
                            width = 1752,
                            authors = {
                                {
                                    handle = "mukinky",
                                    display_name = "mukinky",
                                    profile_url = "https://e621.net/posts?tags=mukinky",
                                },
                            },
                            rating = DbUtil.k.Rating.Explicit,
                            thumbnails = {
                                {
                                    height = 150,
                                    raw_uri = "https://static1.e621.net/data/preview/dc/90/dc90a909c40a2c602143dbf765c2074f.jpg",
                                    scale = 1,
                                    width = 124,
                                },
                            },
                            incoming_tags = {
                                "accessories_only",
                                "accessory",
                                "anal",
                                "anal_orgasm",
                                "anal_penetration",
                                "animal_genitalia",
                                "animal_penis",
                                "animal_pussy",
                                "anthro",
                                "anthro_on_feral",
                                "anthro_on_top",
                                "anthro_penetrating",
                                "anthro_penetrating_feral",
                                "anus",
                                "aroused",
                                "ass_up",
                                "balls",
                                "bestiality",
                                "big_balls",
                                "biped",
                                "bodily_fluids",
                                "butt",
                                "canine_cocksleeve",
                                "canine_genitalia",
                                "canine_penis",
                                "canine_pussy",
                                "close-up",
                                "cocksleeve_in_ass",
                                "cocksleeve_insertion",
                                "cum",
                                "cum_drip",
                                "cum_in_ass",
                                "cum_inside",
                                "cum_while_penetrated",
                                "digitigrade",
                                "doggystyle",
                                "dripping",
                                "duo",
                                "ejaculation",
                                "erection",
                                "feral",
                                "feral_on_bottom",
                                "feral_penetrated",
                                "from_behind_position",
                                "from_front_position",
                                "genital_fluids",
                                "genitals",
                                "hair",
                                "hands-free",
                                "head_down_ass_up",
                                "herm",
                                "herm/male",
                                "herm_on_feral",
                                "herm_on_top",
                                "herm_penetrating",
                                "herm_penetrating_male",
                                "huge_balls",
                                "insertable_sex_toy",
                                "intersex",
                                "intersex/male",
                                "intersex_on_feral",
                                "intersex_on_top",
                                "intersex_penetrating",
                                "intersex_penetrating_male",
                                "kerchief",
                                "knot",
                                "larger_feral",
                                "larger_male",
                                "leaking",
                                "leaking_cum",
                                "leaking_precum",
                                "leaking_pussy",
                                "looking_pleasured",
                                "lying",
                                "male",
                                "male/male",
                                "male_penetrated",
                                "male_penetrating",
                                "male_penetrating_male",
                                "mane",
                                "mane_hair",
                                "missionary_position",
                                "multi_nipple",
                                "nipples",
                                "nude",
                                "object_in_ass",
                                "on_back",
                                "on_bottom",
                                "on_front",
                                "on_ground",
                                "on_top",
                                "orgasm",
                                "pawpads",
                                "paws",
                                "penetrable_sex_toy",
                                "penetration",
                                "penetration_tunneling",
                                "penile",
                                "penile_penetration",
                                "penis",
                                "penis_in_ass",
                                "plantigrade",
                                "precum",
                                "precum_drip",
                                "precum_on_penis",
                                "pussy",
                                "quadruped",
                                "raised_leg",
                                "raised_tail",
                                "sex",
                                "sex_toy",
                                "sex_toy_in_ass",
                                "sex_toy_insertion",
                                "sex_toy_penetration",
                                "sheath",
                                "simultaneous_orgasms",
                                "size_difference",
                                "smaller_anthro",
                                "smaller_herm",
                                "smaller_intersex",
                                "smaller_on_top",
                                "tail",
                                "teats",
                                "ursine_penis",
                                "vaginal_fluids",
                                "vixenmaker",
                                "kuruk_(character)",
                                "skylar_(character)",
                                "bear",
                                "brown_bear",
                                "canid",
                                "canine",
                                "canis",
                                "domestic_dog",
                                "grizzly_bear",
                                "husky",
                                "hybrid",
                                "mammal",
                                "nordic_sled_dog",
                                "spitz",
                                "tervuren",
                                "ursine",
                                "hi_res",
                                "nonbinary_(lore)",
                            },
                        },
                    },
                },
                nil,
            },
        },
        {
            input = { inputPool },
            expected = { expectedPool, nil },
        },
    }
    local regular_response_body = Slurp("test/e6_regular_example.json")
    local mocks = {
        fetch_mock_head_html_200(inputRegular),
        fetch_mock_head_html_200(inputQueryParams),
        fetch_mock_head_html_200(inputVideo),
        fetch_mock_head_html_200(inputGif),
        fetch_mock_head_html_200(inputThirdPartyEdit),
        fetch_mock_head_html_200(inputPool),
        {
            whenCalledWith = inputRegular .. ".json",
            thenReturn = { 200, {}, regular_response_body },
        },
        {
            whenCalledWith = inputQueryParamsWithJson,
            thenReturn = { 200, {}, regular_response_body },
        },
        {
            whenCalledWith = inputVideo .. ".json",
            thenReturn = { 200, {}, Slurp("test/e6_video_example.json") },
        },
        {
            whenCalledWith = inputGif .. ".json",
            thenReturn = { 200, {}, Slurp("test/e6_gif_example.json") },
        },
        {
            whenCalledWith = inputThirdPartyEdit .. ".json",
            thenReturn = { 200, {}, Slurp("test/e6_third_party_edit.json") },
        },
        {
            whenCalledWith = inputPool .. ".json",
            thenReturn = {
                200,
                {},
                [[{"id":40574,"name":"Eclipse_the_Mightyena","created_at":"2024-05-05T21:25:57.601-04:00","updated_at":"2024-05-05T21:25:57.601-04:00","creator_id":414785,"description":"A small miniseries of Eclipse the Mightyena taunting his trainer","is_active":true,"category":"series","post_ids":[4763407,4764946],"creator_name":"64k","post_count":2}]],
            },
        },
        {
            whenCalledWith = "https://e621.net/posts/4763407.json",
            thenReturn = { 200, {}, Slurp("test/e6_pool_1.json") },
        },
        {
            whenCalledWith = "https://e621.net/posts/4764946.json",
            thenReturn = { 200, {}, Slurp("test/e6_pool_2.json") },
        },
    }
    process_entry_framework(tests, mocks)
end

function TestScraperPipeline:testValidCohostLinks()
    local inputSFW =
        "https://cohost.org/TuxedoDragon/post/5682670-something-something"
    local inputNSFW =
        "https://cohost.org/Puptini/post/5584885-did-you-wonder-where"
    local inputLoggedInOnly =
        "https://cohost.org/infinityio/post/4685920-div-style-flex-dir"
    local tests = {
        {
            input = { inputSFW },
            expected = {
                {
                    fetch = {
                        {
                            kind = DbUtil.k.ImageKind.Image,
                            authors = {
                                {
                                    display_name = "Tux!! (certified tf hazard >:3)",
                                    handle = "TuxedoDragon",
                                    profile_url = "https://cohost.org/TuxedoDragon",
                                },
                            },
                            canonical_domain = "cohost.org",
                            incoming_tags = {
                                "vee!~",
                                "tux arts",
                                "eevee",
                                "pokesona",
                                "pmd",
                                "pokemon",
                            },
                            height = 800,
                            mime_type = "image/png",
                            raw_image_uri = "https://staging.cohostcdn.org/attachment/bc0436cc-262d-47a1-b444-f954a3f81c6c/eyes.png",
                            this_source = "https://cohost.org/TuxedoDragon/post/5682670-something-something",
                            width = 1630,
                            rating = DbUtil.k.Rating.General,
                        },
                    },
                },
                nil,
            },
        },
        {
            input = { inputNSFW },
            expected = {
                {
                    fetch = {
                        {
                            kind = DbUtil.k.ImageKind.Image,
                            authors = {
                                {
                                    display_name = "Annie",
                                    handle = "Puptini",
                                    profile_url = "https://cohost.org/Puptini",
                                },
                            },
                            canonical_domain = "cohost.org",
                            height = 1280,
                            mime_type = "image/png",
                            raw_image_uri = "https://staging.cohostcdn.org/attachment/40e2ebfc-a548-458d-abde-6551929a6ae3/tumblr_nbrmyhYBa41t46mxyo2_1280.png",
                            this_source = "https://cohost.org/Puptini/post/5584885-did-you-wonder-where",
                            width = 1280,
                            rating = DbUtil.k.Rating.Explicit,
                            incoming_tags = {
                                "pokeverse",
                                "Bayli",
                                "scars",
                                "Astar",
                                "tyranitar",
                                "pkmn",
                                "pokephilia",
                                "size difference",
                                "stomach bulge",
                                "torn clothes",
                                "torn stockings",
                                "cum",
                                "Piercings",
                                "smoking",
                                "sequence",
                                "nsfw",
                                "annie art",
                                "annie OCs",
                            },
                        },
                        {
                            kind = DbUtil.k.ImageKind.Image,
                            authors = {
                                {
                                    display_name = "Annie",
                                    handle = "Puptini",
                                    profile_url = "https://cohost.org/Puptini",
                                },
                            },
                            canonical_domain = "cohost.org",
                            height = 1200,
                            mime_type = "image/png",
                            raw_image_uri = "https://staging.cohostcdn.org/attachment/0164799d-c699-48fd-bdaf-558f6f947aa3/bayli%20aftersex%20resize.png",
                            this_source = "https://cohost.org/Puptini/post/5584885-did-you-wonder-where",
                            width = 857,
                            rating = DbUtil.k.Rating.Explicit,
                            incoming_tags = {
                                "pokeverse",
                                "Bayli",
                                "scars",
                                "Astar",
                                "tyranitar",
                                "pkmn",
                                "pokephilia",
                                "size difference",
                                "stomach bulge",
                                "torn clothes",
                                "torn stockings",
                                "cum",
                                "Piercings",
                                "smoking",
                                "sequence",
                                "nsfw",
                                "annie art",
                                "annie OCs",
                            },
                        },
                    },
                },
                nil,
            },
        },
        {
            input = { inputLoggedInOnly },
            expected = {
                nil,
                PermScraperError(
                    "This user's posts are only visible when logged in."
                ),
            },
        },
    }
    local mocks = {
        fetch_mock_head_html_200(inputSFW),
        fetch_mock_head_html_200(inputNSFW),
        fetch_mock_head_html_200(inputLoggedInOnly),
        {
            whenCalledWith = "https://cohost.org/api/v1/trpc/posts.singlePost?batch=1&input=%7B%220%22%3A%7B%22handle%22%3A%22TuxedoDragon%22%2C%22postId%22%3A5682670%7D%7D",
            thenReturn = { 200, {}, Slurp("test/cohost_sfw.json") },
        },
        {
            whenCalledWith = "https://cohost.org/api/v1/trpc/posts.singlePost?batch=1&input=%7B%220%22%3A%7B%22handle%22%3A%22Puptini%22%2C%22postId%22%3A5584885%7D%7D",
            thenReturn = { 200, {}, Slurp("test/cohost_nsfw.json") },
        },
        {
            whenCalledWith = "https://cohost.org/api/v1/trpc/posts.singlePost?batch=1&input=%7B%220%22%3A%7B%22handle%22%3A%22infinityio%22%2C%22postId%22%3A4685920%7D%7D",
            thenReturn = { 200, {}, Slurp("test/cohost_loggedinonly.json") },
        },
    }
    process_entry_framework(tests, mocks)
end

function TestScraperPipeline:testItakuEEWorks()
    local input_nsfw = "https://itaku.ee/images/164381"
    local tests = {
        {
            input = { input_nsfw },
            expected = {
                {
                    fetch = {
                        {
                            kind = DbUtil.k.ImageKind.Image,
                            authors = {
                                {
                                    display_name = "Carpetwurm",
                                    handle = "carpetwurm",
                                    profile_url = "https://itaku.ee/profile/carpetwurm",
                                },
                            },
                            canonical_domain = "itaku.ee",
                            incoming_tags = {
                                "male",
                                "canine",
                                "furry",
                                "duo",
                                "commission",
                                "huge_ass",
                                "big_butt",
                                "penis",
                                "balls",
                                "testicles",
                                "anus",
                                "male/male",
                                "gay",
                                "homosexual",
                                "equine_penis",
                                "background",
                                "public",
                                "sweat",
                                "musk",
                                "donut_ring",
                                "yiff",
                                "exhibitionism",
                                "musky",
                                "musk",
                                "horsecock",
                                "equine_penis",
                                "subway",
                            },
                            height = 5100,
                            mime_type = "image/jpeg",
                            image_data = "elided",
                            raw_image_uri = "https://itaku.ee/api/media/gallery_imgs/C_Runic_Kshalin_uXs0Ssb.jpg",
                            this_source = input_nsfw,
                            width = 3300,
                            rating = DbUtil.k.Rating.Explicit,
                        },
                    },
                },
                nil,
            },
        },
    }
    local mocks = {
        fetch_mock_head_html_200(input_nsfw),
        {
            whenCalledWith = "https://itaku.ee/api/galleries/images/164381/?format=json",
            thenReturn = { 200, {}, Slurp("test/itakuee_nsfw.json") },
        },
        {
            whenCalledWith = "https://itaku.ee/api/media/gallery_imgs/C_Runic_Kshalin_uXs0Ssb.jpg",
            thenReturn = {
                200,
                { ["Content-Type"] = "image/jpeg" },
                Slurp("test/itakuee_nsfw.jpg"),
            },
        },
    }
    process_entry_framework(tests, mocks)
end

function TestScraperPipeline:testValidMastodonLinks()
    local input_image = "https://gulp.cafe/@greedygulo/112300431726424371"
    local input_gifv = "https://thicc.horse/@QuanZillan/112697596954622744"
    local tests = {
        {
            input = { input_image },
            expected = {
                {
                    fetch = {
                        {
                            authors = {
                                {
                                    display_name = "GreedyGulo",
                                    handle = "greedygulo",
                                    profile_url = "https://gulp.cafe/@greedygulo",
                                },
                            },
                            canonical_domain = "gulp.cafe",
                            height = 1900,
                            incoming_tags = {
                                "furryart",
                                "yiff",
                                "transformation",
                                "condomtf",
                                "objecttf",
                            },
                            kind = 1,
                            mime_type = "image/png",
                            rating = 3,
                            raw_image_uri = "https://cdn.masto.host/gulpcafe/media_attachments/files/112/300/431/644/077/575/original/2f271e53889f543e.png",
                            this_source = "https://gulp.cafe/@greedygulo/112300431726424371",
                            thumbnails = {
                                {
                                    height = 436,
                                    raw_uri = "https://cdn.masto.host/gulpcafe/media_attachments/files/112/300/431/644/077/575/small/2f271e53889f543e.png",
                                    scale = 1,
                                    width = 528,
                                },
                            },
                            width = 2300,
                        },
                    },
                },
                nil,
            },
        },
        {
            input = { input_gifv },
            expected = {
                {
                    fetch = {
                        {
                            authors = {
                                {
                                    display_name = "Xillin",
                                    handle = "QuanZillan",
                                    profile_url = "https://thicc.horse/@QuanZillan",
                                },
                            },
                            canonical_domain = "thicc.horse",
                            height = 620,
                            incoming_tags = {
                                "horsecock",
                                "infestation",
                                "animation",
                                "Art",
                                "furry",
                                "porn",
                                "nsfw",
                                "horse",
                                "worms",
                            },
                            kind = 5,
                            mime_type = "video/mp4",
                            rating = 3,
                            raw_image_uri = "https://files.thicc.horse/media_attachments/files/112/697/583/091/298/258/original/509430b0cf6f1d1e.mp4",
                            this_source = "https://thicc.horse/@QuanZillan/112697596954622744",
                            thumbnails = {
                                {
                                    height = 453,
                                    raw_uri = "https://files.thicc.horse/media_attachments/files/112/697/583/091/298/258/small/509430b0cf6f1d1e.png",
                                    scale = 1,
                                    width = 640,
                                },
                            },
                            width = 876,
                        },
                    },
                },
                nil,
            },
        },
    }
    local mocks = {
        fetch_mock_head_html_200(input_image),
        fetch_mock_head_html_200(input_gifv),
        {
            whenCalledWith = "https://thicc.horse/api/v1/statuses/112697596954622744",
            thenReturn = { 200, {}, Slurp("test/mastodon_gifv.json") },
        },
        {
            whenCalledWith = "https://gulp.cafe/api/v1/statuses/112300431726424371",
            thenReturn = { 200, {}, Slurp("test/mastodon_image.json") },
        },
    }
    process_entry_framework(tests, mocks)
end

function TestScraperPipeline:testDeviantArt()
    local case1 =
        "https://www.deviantart.com/teonocturnal/art/Game-day-1062228118"
    local tests = {
        {
            input = { case1 },
            expected = {
                {
                    fetch = {
                        {
                            authors = {
                                {
                                    display_name = "TeoNocturnal",
                                    handle = "TeoNocturnal",
                                    profile_url = "https://www.deviantart.com/TeoNocturnal",
                                },
                            },
                            canonical_domain = "www.deviantart.com",
                            height = 1074,
                            incoming_tags = {
                                "digitalart",
                                "digitalpainting",
                                "dragonanthro",
                                "dragonwings",
                                "fireplace",
                                "naga",
                                "sunlight",
                                "threeheaded",
                                "cobraanthro",
                                "cozyillustration",
                            },
                            kind = 1,
                            rating = 1,
                            raw_image_uri = "https://wixmp-ed30a86b8c4ca887773594c2.wixmp.com/f/80db4200-0dd8-41af-b0c2-e317a8864c8c/dhkf8gm-4b6dfb0a-4b73-4efa-8b88-dcbb3c07f761.png",
                            this_source = case1,
                            width = 1600,
                        },
                    },
                },
                nil,
            },
        },
    }
    local mocks = {
        {
            whenCalledWith = case1,
            thenReturn = { 200, {}, Slurp("test/da_deviation.html") },
        },
        {
            whenCalledWith = "https://www.deviantart.com/oauth2/token?grant_type=client_credentials&client_id&client_secret",
            thenReturn = { 200, {}, Slurp("test/da_token.json") },
        },
        {
            whenCalledWith = "https://www.deviantart.com/api/v1/oauth2/deviation/A8E4E11D-7B04-37B0-1455-70BD21C6AE1A?with_session=0",
            thenReturn = { 200, {}, Slurp("test/da_deviation.json") },
        },
        {
            whenCalledWith = "https://www.deviantart.com/api/v1/oauth2/deviation/download/A8E4E11D-7B04-37B0-1455-70BD21C6AE1A",
            thenReturn = { 200, {}, Slurp("test/da_download.json") },
        },
        {
            whenCalledWith = "https://www.deviantart.com/api/v1/oauth2/deviation/metadata?deviationids=A8E4E11D-7B04-37B0-1455-70BD21C6AE1A&ext_submission=1&with_session=0",
            thenReturn = { 200, {}, Slurp("test/da_metadata.json") },
        },
    }
    process_entry_framework(tests, mocks)
end

--[[
TestMultipart = {}
function TestMultipart:testEncode()
    local body, boundary = multipart.encode { foo = "bar" }
    local status, headers, resp_body = Fetch("http://httpbin.org/post", {
        method = "POST",
        body = body,
        headers = {
            ["Content-Type"] = string.format(
                'multipart/form-data; boundary="%s"',
                boundary
            ),
        },
    })
    luaunit.assertEquals(status, 200)
    local json, err = DecodeJson(resp_body)
    luaunit.assertIsNil(err)
    luaunit.assertNotIsNil(json)
    luaunit.assertEquals(json.form, { foo = "bar" })
end

function TestMultipart:testEncodeForTelegram()
    local body, boundary = multipart.encode {
        photo = {
            -- filename = "C:\\fakepath\\purple.jpg",
            data = "hello worldJFIF",
        },
    }
    local status, headers, resp_body = Fetch("http://httpbin.org/post", {
        method = "POST",
        body = body,
        headers = {
            ["Content-Type"] = string.format(
                'multipart/form-data; boundary="%s"',
                boundary
            ),
        },
    })
    luaunit.assertEquals(status, 200)
    local json, err = DecodeJson(resp_body)
    luaunit.assertIsNil(err)
    luaunit.assertNotIsNil(json)
    luaunit.assertEquals(json.form, { photo = "hello worldJFIF" })
end
]]

TestTgBot = {}
function TestTgBot:testfindAllLinksOnFoxbotMessage()
    local input = DecodeJson(Slurp("test/foxbot_tg_message.json"))
    local expected = {
        "https://www.furaffinity.net/view/56537131/",
        "https://e621.net/posts/4766158",
    }
    local actual = bot.get_all_links_from_message(input)
    luaunit.assertEquals(actual, expected)
end

function TestTgBot:testfindAllLinksOnBotButtonMessage()
    local input = DecodeJson(Slurp("test/bot_button_tg_message.json"))
    local expected = {
        "https://www.furaffinity.net/view/50644834/",
        "https://e621.net/posts/3817467",
    }
    local actual = bot.get_all_links_from_message(input)
    luaunit.assertEquals(actual, expected)
end

os.exit(luaunit.run())
