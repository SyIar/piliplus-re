import Foundation
import XCTest
import PiliPlaybackCore

@testable import bili

final class BiliAPIClientRequestContractTests: H264PlaybackTestCase {
    @MainActor
    func testSearchFilterApplyBatchesChangesAndKeepsSubmittedKeyword() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(for: request, body: #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#)
            }
            return Self.response(for: request, body: #"{"code":0,"data":{"result":[]}}"#)
        }
        defer { RequestContractURLProtocol.reset() }
        let suite = "SearchFilterApplyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SearchViewModel(api: try makeAPI(cookieHeader: ""), historyDefaults: defaults)

        // Changing filters before a submission must not create a network request.
        await model.applyFilters(scope: .video, order: .comprehensive, duration: .any)
        XCTAssertTrue(recorder.requests.isEmpty)
        let keyword = "layout-\(UUID().uuidString)"
        await model.search(keyword)
        model.query = "unsubmitted edit"
        await model.applyFilters(scope: .video, order: .newest, duration: .long)
        XCTAssertEqual(model.state, .loaded)
        let searches = recorder.requests.filter { Self.queryValues(for: $0)["search_type"] == "video" }
        XCTAssertEqual(searches.count, 2, "Initial search plus one batched Apply")
        let request = try XCTUnwrap(searches.last)
        XCTAssertEqual(Self.queryValues(for: request)["keyword"], keyword)
        XCTAssertEqual(Self.queryValues(for: request)["order"], "pubdate")
        XCTAssertEqual(Self.queryValues(for: request)["duration"], "3")
        let previousCount = recorder.requests.count
        await model.applyFilters(scope: .video, order: .newest, duration: .long)
        XCTAssertEqual(recorder.requests.count, previousCount, "Unchanged filters must not refetch")
    }

    @MainActor
    func testHistorySubmissionSurvivesNativeFieldEchoAndOnlyFetchesSelectedTab() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(for: request, body: #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#)
            }
            return Self.response(for: request, body: #"{"code":0,"data":{"result":[]}}"#)
        }
        defer { RequestContractURLProtocol.reset() }
        let suite = "SearchHistoryEcho.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SearchViewModel(api: try makeAPI(cookieHeader: ""), historyDefaults: defaults)
        XCTAssertEqual(model.selectedScope, .video)
        let keyword = "history-\(UUID().uuidString)"
        await model.search(keyword)
        model.queryChanged()
        XCTAssertEqual(model.state, .loaded)
        XCTAssertFalse(model.showsDiscovery)
        XCTAssertEqual(model.searchHistory.first, keyword)
        var searches = recorder.requests.filter { Self.queryValues(for: $0)["search_type"] != nil }
        XCTAssertEqual(searches.count, 1)
        XCTAssertEqual(Self.queryValues(for: try XCTUnwrap(searches.last))["search_type"], "video")
        await model.selectScope(.user)
        searches = recorder.requests.filter { Self.queryValues(for: $0)["search_type"] != nil }
        XCTAssertEqual(Self.queryValues(for: try XCTUnwrap(searches.last))["search_type"], "bili_user")
        XCTAssertEqual(Self.queryValues(for: try XCTUnwrap(searches.last))["keyword"], keyword)
    }

    override func tearDown() {
        RequestContractURLProtocol.reset()
        super.tearDown()
    }

    @MainActor
    func testSearchSuggestBuildsStableEncodedQueryForwardsHeadersAndDecodes() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "search request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            guard request.url?.path == "/x/web-interface/search/suggest" else {
                return Self.response(
                    for: request,
                    body: #"{"code":-404,"message":"unexpected"}"#
                )
            }
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"message":"0","data":{"tag":[{"value":"\u{6d4b}\u{8bd5}\u{7ed3}\u{679c}","ref":7}]}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let cookieHeader = "SESSDATA=session-value; DedeUserID=1001; buvid3=buvid-value"
        let api = try makeAPI(cookieHeader: cookieHeader)
        let term = "A+B & \u{4e2d}/\u{6587}"
        let suggestions = try await api.fetchSearchSuggest(term: term)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(suggestions.map(\.value), ["\u{6d4b}\u{8bd5}\u{7ed3}\u{679c}"])
        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.host, "api.bilibili.com")
        XCTAssertEqual(url.path, "/x/web-interface/search/suggest")
        XCTAssertEqual(
            components.queryItems,
            [
                URLQueryItem(name: "highlight", value: ""),
                URLQueryItem(name: "main_ver", value: "v1"),
                URLQueryItem(name: "term", value: term),
            ]
        )
        XCTAssertEqual(
            components.percentEncodedQuery,
            "highlight=&main_ver=v1&term=A+B%20%26%20%E4%B8%AD/%E6%96%87"
        )
        XCTAssertEqual(
            cookieValues(in: request.value(forHTTPHeaderField: "Cookie")),
            cookieValues(in: cookieHeader)
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.bilibili.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://www.bilibili.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json, text/plain, */*")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "User-Agent"),
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        )
    }

    @MainActor
    func testSearchHotSearchPropagatesAPIErrorResponse() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "search API error captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}
                        """
                )
            }
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":-352,"message":"\u{98ce}\u{63a7}\u{6821}\u{9a8c}\u{5931}\u{8d25}","data":null}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value")

        do {
            _ = try await api.fetchHotSearch()
            XCTFail("Expected the API error to be propagated")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -352)
            XCTAssertEqual(message, "\u{98ce}\u{63a7}\u{6821}\u{9a8c}\u{5931}\u{8d25}")
        }

        await fulfillment(of: [requestExpectation], timeout: 2)
        XCTAssertEqual(recorder.request?.url?.path, "/x/web-interface/wbi/search/square")
    }

    @MainActor
    func testMainCommentsBuildsRequestAndDecodesPaginationAndComments() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "main comments request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"replies":[{"rpid":12345,"like":9,"action":1}],"top_replies":[],"cursor":{"next":"next-cursor","is_end":false}}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value")
        let cursor = "cursor/with+symbols"
        let page = try await api.fetchComments(oid: "456", type: 11, cursor: cursor, sort: .hot)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(page.replies?.map(\.id), [12345])
        XCTAssertEqual(page.replies?.first?.like, 9)
        XCTAssertEqual(page.replies?.first?.likeState, 1)
        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.path, "/x/v2/reply/main")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        var query = Self.queryValues(in: components)
        let pagination = try XCTUnwrap(query.removeValue(forKey: "pagination_str"))
        let paginationObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(pagination.utf8)) as? [String: String]
        )
        XCTAssertEqual(paginationObject, ["offset": cursor])
        XCTAssertEqual(
            query,
            [
                "oid": "456",
                "type": "11",
                "mode": "3",
                "plat": "1",
            ]
        )
    }

    @MainActor
    func testCommentRepliesBuildsPagingAndTimeSortRequestAndDecodes() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "comment replies request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"replies":[{"rpid":67890,"like":4,"action":"1"}],"top_replies":[]}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let page = try await api.fetchCommentReplies(
            oid: "456",
            type: 11,
            root: 987,
            page: 3,
            sort: .time
        )

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(page.replies?.map(\.id), [67890])
        XCTAssertEqual(page.replies?.first?.like, 4)
        XCTAssertEqual(page.replies?.first?.likeState, 1)
        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.path, "/x/v2/reply/reply")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(
            Self.queryValues(in: components),
            [
                "oid": "456",
                "type": "11",
                "root": "987",
                "pn": "3",
                "ps": "20",
                "sort": "1",
            ]
        )
    }

    @MainActor
    func testCommentDialogBuildsRequestAndDecodesResponse() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "comment dialog request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"replies":[{"rpid":24680,"like":6,"action":1}],"top_replies":[]}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value")
        let page = try await api.fetchCommentDialog(oid: "321", type: 1, root: 654, dialog: 987, size: 12)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(page.replies?.map(\.id), [24680])
        XCTAssertEqual(page.replies?.first?.like, 6)
        XCTAssertEqual(page.replies?.first?.likeState, 1)
        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.path, "/x/v2/reply/dialog/cursor")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(
            Self.queryValues(in: components),
            [
                "oid": "321",
                "type": "1",
                "root": "654",
                "dialog": "987",
                "size": "12",
            ]
        )
    }

    @MainActor
    func testCommentsRepliesAndDialogForwardExplicitCookieHeader() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "comment reads captured")
        requestExpectation.expectedFulfillmentCount = 3
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"replies":[{"rpid":13579}],"top_replies":[]}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=main-session; DedeUserID=1001")
        let interactionCookieHeader = "SESSDATA=interaction-session; DedeUserID=2002"
        let comments = try await api.fetchComments(
            oid: "456",
            type: 11,
            cookieHeader: interactionCookieHeader
        )
        let replies = try await api.fetchCommentReplies(
            oid: "456",
            type: 11,
            root: 987,
            cookieHeader: interactionCookieHeader
        )
        let dialog = try await api.fetchCommentDialog(
            oid: "456",
            type: 11,
            root: 987,
            dialog: 13579,
            cookieHeader: interactionCookieHeader
        )

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(comments.replies?.map(\.id), [13579])
        XCTAssertEqual(replies.replies?.map(\.id), [13579])
        XCTAssertEqual(dialog.replies?.map(\.id), [13579])
        XCTAssertEqual(recorder.requests.count, 3)
        for request in recorder.requests {
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(
                cookieValues(in: request.value(forHTTPHeaderField: "Cookie")),
                ["SESSDATA": "interaction-session", "DedeUserID": "2002"]
            )
        }
    }

    @MainActor
    func testCommentReadsUseSelectedInteractionAccountByDefault() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "interaction account comment reads captured")
        requestExpectation.expectedFulfillmentCount = 3
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"replies":[{"rpid":13579,"like":10,"action":1,"like_state":0}],"top_replies":[]}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=main-session; bili_jct=main-csrf; DedeUserID=1001",
            configure: { sessionStore, libraryStore in
                _ = try sessionStore.saveAdditionalAccount([
                    Self.makeCookie(name: "buvid3", value: "interaction-device"),
                    Self.makeCookie(name: "DedeUserID", value: "2002"),
                    Self.makeCookie(name: "SESSDATA", value: "interaction-session"),
                    Self.makeCookie(name: "bili_jct", value: "interaction-csrf"),
                ])
                try sessionStore.selectInteractionAccount(mid: 2002)
                libraryStore.setMultiAccountExperimentEnabled(true)
            }
        )

        async let comments = api.fetchComments(oid: "456", type: 11)
        async let replies = api.fetchCommentReplies(oid: "456", type: 11, root: 987)
        async let dialog = api.fetchCommentDialog(oid: "456", type: 11, root: 987, dialog: 13579)
        let pages = try await (comments, replies, dialog)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(pages.0.replies?.first?.like, 10)
        XCTAssertEqual(pages.0.replies?.first?.likeState, 1)
        XCTAssertEqual(recorder.requests.count, 3)
        for request in recorder.requests {
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            let cookies = cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertEqual(cookies["DedeUserID"], "2002")
            XCTAssertEqual(cookies["SESSDATA"], "interaction-session")
        }
    }

    @MainActor
    func testCommentDialogPropagatesAPIError() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "comment dialog error captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":-404,"message":"\u{8bc4}\u{8bba}\u{4e0d}\u{5b58}\u{5728}","data":null}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value")
        do {
            _ = try await api.fetchCommentDialog(oid: "999", type: 1, root: 1000, dialog: 1001)
            XCTFail("Expected the API error to be propagated")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -404)
            XCTAssertEqual(message, "\u{8bc4}\u{8bba}\u{4e0d}\u{5b58}\u{5728}")
        }

        await fulfillment(of: [requestExpectation], timeout: 2)
        XCTAssertEqual(recorder.request?.url?.path, "/x/v2/reply/dialog/cursor")
    }

    @MainActor
    func testDynamicFeedBuildsFirstPageAndOffsetPaginationRequests() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "dynamic feed requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            guard request.url?.path == "/x/polymer/web-dynamic/v1/feed/all" else {
                throw URLError(.badServerResponse)
            }
            requestExpectation.fulfill()
            let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "offset" })?
                .value
            let responseOffset = offset == nil ? "next-offset" : "final-offset"
            let hasMore = offset == nil ? "true" : "false"
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"items":[],"has_more":\(hasMore),"offset":"\(responseOffset)"}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let firstPage = try await api.fetchDynamicFeed()
        let nextPage = try await api.fetchDynamicFeed(offset: "next-offset")

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(firstPage.offset, "next-offset")
        XCTAssertEqual(nextPage.offset, "final-offset")
        let requests = recorder.requests
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.path, "/x/polymer/web-dynamic/v1/feed/all")
            let cookies = cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertEqual(cookies["SESSDATA"], "session-value")
            XCTAssertEqual(cookies["DedeUserID"], "1001")
        }
        let firstRequest = try XCTUnwrap(
            requests.first(where: {
                guard let components = URLComponents(url: $0.url!, resolvingAgainstBaseURL: false) else {
                    return false
                }
                return Self.queryValues(in: components)["offset"] == nil
            })
        )
        let firstQuery = try XCTUnwrap(URLComponents(url: firstRequest.url!, resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            Self.queryValues(in: firstQuery),
            [
                "features":
                    "itemOpusStyle,listOnlyfans,opusBigCover,onlyfansVote,decorationCard,onlyfansAssetsV2,forwardListHidden,ugcDelete",
                "platform": "web",
                "type": "all",
                "web_location": "333.1365",
            ]
        )
        let secondRequest = try XCTUnwrap(
            requests.first(where: {
                guard let components = URLComponents(url: $0.url!, resolvingAgainstBaseURL: false) else {
                    return false
                }
                return Self.queryValues(in: components)["offset"] == "next-offset"
            })
        )
        let secondQuery = try XCTUnwrap(URLComponents(url: secondRequest.url!, resolvingAgainstBaseURL: false))
        XCTAssertEqual(Self.queryValues(in: secondQuery)["offset"], "next-offset")
    }

    @MainActor
    func testDynamicPortalBuildsRequestAndDecodes() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "dynamic portal request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        _ = try await api.fetchDynamicPortal()

        await fulfillment(of: [requestExpectation], timeout: 2)

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/polymer/web-dynamic/v1/portal")
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            Self.queryValues(in: components),
            ["up_list_more": "1", "web_location": "333.1365"]
        )
        XCTAssertEqual(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"], "session-value")
    }

    @MainActor
    func testAccountHistoryBuildsFirstPageAndCursorPaginationRequests() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "account history requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            let query = Self.queryValues(for: request)
            if query["max"] == "0" {
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"list":[{"bvid":"BVfirst","aid":101,"title":"\u{7b2c}\u{4e00}\u{6761}","view_at":1700000000}]}}
                        """
                )
            }
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"list":[{"bvid":"BVsecond","aid":100,"title":"\u{7b2c}\u{4e8c}\u{6761}","view_at":1699999000}]}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let entries = try await api.fetchAccountHistory(page: 2, pageSize: 1)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(entries.map(\.bvid), ["BVsecond"])
        XCTAssertEqual(recorder.requests.count, 2)
        let firstQuery = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(recorder.requests[0].url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            Self.queryValues(in: firstQuery),
            [
                "type": "archive",
                "ps": "1",
                "max": "0",
                "view_at": "0",
            ])
        let secondQuery = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(recorder.requests[1].url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            Self.queryValues(in: secondQuery),
            [
                "type": "archive",
                "ps": "1",
                "max": "101",
                "view_at": "1700000000",
            ])
        XCTAssertEqual(
            cookieValues(in: recorder.requests[0].value(forHTTPHeaderField: "Cookie"))["SESSDATA"], "session-value")
    }

    @MainActor
    func testAccountFavoritesBuildFolderListAndDeduplicateAcrossFolders() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "account favorite requests captured")
        requestExpectation.expectedFulfillmentCount = 3
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            switch request.url?.path {
            case "/x/v3/fav/folder/created/list-all":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"list":[{"id":7},{"id":8}]}}
                        """
                )
            case "/x/v3/fav/resource/list":
                let folderID = Self.queryValues(for: request)["media_id"]
                let body =
                    folderID == "7"
                    ? """
                    {"code":0,"data":{"medias":[{"bvid":"BVone","aid":1},{"bvid":"BVtwo","aid":2}]}}
                    """
                    : """
                    {"code":0,"data":{"medias":[{"bvid":"BVtwo","aid":2},{"bvid":"BVthree","aid":3}]}}
                    """
                return Self.response(for: request, body: body)
            default:
                throw URLError(.badServerResponse)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let entries = try await api.fetchAccountFavorites(page: 2, pageSize: 3)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(entries.map(\.bvid), ["BVone", "BVtwo", "BVthree"])
        XCTAssertEqual(recorder.requests.count, 3)
        let folderQuery = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(recorder.requests[0].url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(Self.queryValues(in: folderQuery), ["up_mid": "1001", "type": "2"])
        let firstFolderQuery = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(recorder.requests[1].url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            Self.queryValues(in: firstFolderQuery),
            [
                "media_id": "7",
                "pn": "2",
                "ps": "3",
                "keyword": "",
                "order": "mtime",
                "type": "0",
                "tid": "0",
                "platform": "web",
            ])
        let favoriteCookieValues = cookieValues(in: recorder.requests[1].value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(favoriteCookieValues["SESSDATA"], "session-value")
        XCTAssertEqual(favoriteCookieValues["DedeUserID"], "1001")
    }

    @MainActor
    func testAccountFavoritesReturnsSuccessfulEntriesWhenAnotherFolderFails() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "partial favorite requests captured")
        requestExpectation.expectedFulfillmentCount = 3
        RequestContractURLProtocol.install { request in
            requestExpectation.fulfill()
            switch request.url?.path {
            case "/x/v3/fav/folder/created/list-all":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"list":[{"id":7},{"id":8}]}}
                        """
                )
            case "/x/v3/fav/resource/list":
                let folderID = Self.queryValues(for: request)["media_id"]
                if folderID == "7" {
                    return Self.response(
                        for: request,
                        body: "{\"code\":-500,\"message\":\"\u{4e34}\u{65f6}\u{5931}\u{8d25}\",\"data\":null}"
                    )
                }
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"medias":[{"bvid":"BVsuccess","aid":3}]}}
                        """
                )
            default:
                throw URLError(.badServerResponse)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let entries = try await api.fetchAccountFavorites(pageSize: 20)

        await fulfillment(of: [requestExpectation], timeout: 2)
        XCTAssertEqual(entries.map(\.bvid), ["BVsuccess"])
    }

    @MainActor
    func testFavoriteFolderPagePropagatesAPIErrorAndBuildsRequest() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "favorite folder error captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":-404,"message":"\u{6536}\u{85cf}\u{5939}\u{4e0d}\u{5b58}\u{5728}","data":null}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        do {
            _ = try await api.fetchFavoriteFolderVideoPage(folderID: 12, page: 3, pageSize: 15)
            XCTFail("Expected the favorite folder API error to be propagated")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -404)
            XCTAssertEqual(message, "\u{6536}\u{85cf}\u{5939}\u{4e0d}\u{5b58}\u{5728}")
        }

        await fulfillment(of: [requestExpectation], timeout: 2)
        let request = try XCTUnwrap(recorder.request)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(Self.queryValues(in: components)["media_id"], "12")
        XCTAssertEqual(Self.queryValues(in: components)["pn"], "3")
        XCTAssertEqual(Self.queryValues(in: components)["ps"], "15")
    }

    @MainActor
    func testAccountHistoryRequiresAuthenticatedHistoryAccount() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            throw URLError(.badServerResponse)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "")
        do {
            _ = try await api.fetchAccountHistoryPage(pageSize: 20)
            XCTFail("Expected account history authentication to be required")
        } catch let error as BiliAPIError {
            guard case .missingSESSDATA = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    @MainActor
    func testUploaderDynamicFeedBuildsSignedRequestWithAuthenticatedCookie() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "uploader dynamic requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                requestExpectation.fulfill()
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/abcdef.png","sub_url":"https://i0.hdslb.com/bfs/wbi/ghijkl.png"}}}
                        """
                )
            }
            guard request.url?.path == "/x/polymer/web-dynamic/v1/feed/space" else {
                throw URLError(.badServerResponse)
            }
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"items":[],"has_more":false,"offset":"space-offset"}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let cookieHeader = "SESSDATA=session-value; DedeUserID=1001"
        let api = try makeAPI(cookieHeader: cookieHeader)
        _ = try await api.refreshPlaybackSigningKeys()
        let page = try await api.fetchUploaderDynamicFeed(mid: 2002, offset: "space-cursor")

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(page.offset, "space-offset")
        let requests = recorder.requests
        XCTAssertEqual(requests.count, 2)
        let uploaderRequest = try XCTUnwrap(requests.last)
        XCTAssertEqual(uploaderRequest.url?.path, "/x/polymer/web-dynamic/v1/feed/space")
        let components = try XCTUnwrap(URLComponents(url: uploaderRequest.url!, resolvingAgainstBaseURL: false))
        let query = Self.queryValues(in: components)
        XCTAssertEqual(query["host_mid"], "2002")
        XCTAssertEqual(query["offset"], "space-cursor")
        XCTAssertEqual(query["platform"], "web")
        XCTAssertEqual(query["web_location"], "333.1387")
        XCTAssertNotNil(query["w_rid"])
        XCTAssertNotNil(query["wts"])
        XCTAssertEqual(uploaderRequest.value(forHTTPHeaderField: "Referer"), "https://space.bilibili.com/2002/dynamic")
        XCTAssertEqual(uploaderRequest.value(forHTTPHeaderField: "Origin"), "https://space.bilibili.com")
        XCTAssertEqual(
            uploaderRequest.value(forHTTPHeaderField: "User-Agent"),
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.2 Safari/605.1.15"
        )
        let uploaderCookies = cookieValues(in: uploaderRequest.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(uploaderCookies["SESSDATA"], "session-value")
        XCTAssertEqual(uploaderCookies["DedeUserID"], "1001")
    }

    @MainActor
    func testDynamicFeedPropagatesAPIError() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "dynamic feed error captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":-352,"message":"\u{98ce}\u{63a7}\u{6821}\u{9a8c}\u{5931}\u{8d25}","data":null}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        do {
            _ = try await api.fetchDynamicFeed(offset: "error-offset")
            XCTFail("Expected the dynamic feed API error to be propagated")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -352)
            XCTAssertEqual(message, "\u{98ce}\u{63a7}\u{6821}\u{9a8c}\u{5931}\u{8d25}")
        }

        await fulfillment(of: [requestExpectation], timeout: 2)
        XCTAssertEqual(recorder.request?.url?.path, "/x/polymer/web-dynamic/v1/feed/all")
    }

    @MainActor
    func testVideoInteractionStateBuildsRelationRequestAndDecodes() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "video relation request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"like":1,"coin":2,"favorite":1,"attention":1}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let state = try await api.fetchVideoInteractionState(aid: 123, bvid: "BV1test")

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertTrue(state.isLiked)
        XCTAssertEqual(state.coinCount, 2)
        XCTAssertTrue(state.isFavorited)
        XCTAssertFalse(state.isFollowing)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/web-interface/archive/relation")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(Self.queryValues(in: components), ["aid": "123", "bvid": "BV1test"])
    }

    @MainActor
    func testVideoLikeBuildsCSRFFormAndRetriesIdempotently() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "like requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        let attempts = RequestContractCounter()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            let currentAttempt = attempts.increment()
            if currentAttempt == 1 {
                throw URLError(.timedOut)
            }
            return Self.response(for: request, body: "{\"code\":0,\"data\":{}}")
        }
        defer { RequestContractURLProtocol.reset() }

        let cookieHeader = "SESSDATA=session-value; bili_jct=csrf-value; DedeUserID=1001"
        let api = try makeAPI(cookieHeader: cookieHeader)
        try await api.toggleVideoLike(aid: 456, liked: true)

        await fulfillment(of: [requestExpectation], timeout: 3)

        XCTAssertEqual(recorder.requests.count, 2)
        for request in recorder.requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/x/web-interface/archive/like")
            XCTAssertEqual(
                formValues(in: request),
                [
                    "aid": "456",
                    "like": "1",
                    "csrf": "csrf-value",
                    "cross_domain": "true",
                    "source": "web_normal",
                    "ga": "1",
                ])
            XCTAssertEqual(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"], "session-value")
            XCTAssertEqual(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["bili_jct"], "csrf-value")
        }
    }

    @MainActor
    func testDynamicLikeBuildsInteractionAccountJSONRequest() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "dynamic like requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(for: request, body: "{\"code\":0,\"data\":{}}")
        }
        defer { RequestContractURLProtocol.reset() }

        let cookieHeader = "SESSDATA=session-value; bili_jct=csrf-value; DedeUserID=1001"
        let api = try makeAPI(cookieHeader: cookieHeader)
        try await api.setDynamicLike(dynamicID: "123456789", liked: true)
        try await api.setDynamicLike(dynamicID: "123456789", liked: false)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(recorder.requests.count, 2)
        for (request, expectedUp) in zip(recorder.requests, [1, 2]) {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/x/dynamic/feed/dyn/thumb")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://t.bilibili.com/123456789")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
            XCTAssertEqual(Self.queryValues(for: request), ["csrf": "csrf-value"])
            let body = try XCTUnwrap(requestBodyData(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["dyn_id_str"] as? String, "123456789")
            XCTAssertEqual(json["up"] as? Int, expectedUp)
            XCTAssertEqual(
                cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"],
                "session-value"
            )
        }
    }

    @MainActor
    func testCommentLikeBuildsInteractionAccountCSRFForm() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "comment like requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(for: request, body: "{\"code\":0,\"data\":{}}")
        }
        defer { RequestContractURLProtocol.reset() }

        let cookieHeader = "SESSDATA=session-value; bili_jct=csrf-value; DedeUserID=1001"
        let api = try makeAPI(cookieHeader: cookieHeader)
        let referer = "https://t.bilibili.com/123456789"
        try await api.setCommentLike(
            oid: " 987654321 ",
            type: 17,
            rpid: 24680,
            liked: true,
            referer: referer
        )
        try await api.setCommentLike(
            oid: "987654321",
            type: 17,
            rpid: 24680,
            liked: false,
            referer: referer
        )

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(recorder.requests.count, 2)
        for (request, expectedAction) in zip(recorder.requests, ["1", "0"]) {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/x/v2/reply/action")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), referer)
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"),
                "application/x-www-form-urlencoded; charset=UTF-8"
            )
            XCTAssertEqual(
                formValues(in: request),
                [
                    "oid": "987654321",
                    "type": "17",
                    "rpid": "24680",
                    "action": expectedAction,
                    "csrf": "csrf-value",
                ]
            )
            XCTAssertEqual(
                cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"],
                "session-value"
            )
        }
    }

    @MainActor
    func testDynamicCommentAddBuildsTopLevelAndReplyForms() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "dynamic comment requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(for: request, body: "{\"code\":0,\"data\":{}}")
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; bili_jct=csrf-value; DedeUserID=1001"
        )
        try await api.addDynamicComment(
            oid: " 987654321 ",
            type: 17,
            message: " \u{9876}\u{7ea7}\u{8bc4}\u{8bba} "
        )
        try await api.addDynamicComment(
            oid: "987654321",
            type: 17,
            message: " \u{56de}\u{590d}\u{5185}\u{5bb9} ",
            root: 101,
            parent: 202
        )

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(recorder.requests.count, 2)
        for request in recorder.requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/x/v2/reply/add")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://t.bilibili.com/")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"),
                "application/x-www-form-urlencoded; charset=UTF-8"
            )
        }
        XCTAssertEqual(
            formValues(in: recorder.requests[0]),
            [
                "oid": "987654321",
                "type": "17",
                "message": "\u{9876}\u{7ea7}\u{8bc4}\u{8bba}",
                "plat": "1",
                "csrf": "csrf-value",
            ]
        )
        XCTAssertEqual(
            formValues(in: recorder.requests[1]),
            [
                "oid": "987654321",
                "type": "17",
                "message": "\u{56de}\u{590d}\u{5185}\u{5bb9}",
                "plat": "1",
                "csrf": "csrf-value",
                "root": "101",
                "parent": "202",
            ]
        )
    }

    @MainActor
    func testDynamicCommentImageUploadDecodesMixedDimensionTypes() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "dynamic comment image upload captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                {"code":0,"data":{"image_url":"//i0.hdslb.com/bfs/dynamic/comment.jpg","image_width":"1920","image_height":1080,"img_size":"512.5"}}
                """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; bili_jct=csrf-value; DedeUserID=1001"
        )
        let image = try await api.uploadDynamicCommentImage(Data([0xFF, 0xD8, 0xFF]))

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests[0].url?.path, "/x/dynamic/feed/draw/upload_bfs")
        XCTAssertEqual(image.imageURL, "https://i0.hdslb.com/bfs/dynamic/comment.jpg")
        XCTAssertEqual(image.width, 1_920)
        XCTAssertEqual(image.height, 1_080)
        XCTAssertEqual(image.size, 512)
    }

    @MainActor
    func testDynamicCommentAddDoesNotRetryAmbiguousPostFailure() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "dynamic comment failure captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            throw URLError(.timedOut)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; bili_jct=csrf-value; DedeUserID=1001"
        )
        do {
            try await api.addDynamicComment(
                oid: "987654321",
                type: 17,
                message: "\u{4e0d}\u{4f1a}\u{81ea}\u{52a8}\u{91cd}\u{8bd5}"
            )
            XCTFail("Expected the network error to be propagated")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }

        await fulfillment(of: [requestExpectation], timeout: 2)
        XCTAssertEqual(recorder.requests.count, 1)
    }

    @MainActor
    func testVideoCoinValidatesMultiplyAndBuildsForm() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "coin request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            guard request.url?.path == "/x/web-interface/coin/add" else {
                return Self.response(
                    for: request,
                    body: #"{"code":-404,"message":"unexpected"}"#
                )
            }
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(for: request, body: "{\"code\":0,\"data\":{}}")
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; bili_jct=csrf-value; DedeUserID=1001")
        do {
            try await api.addVideoCoin(aid: 789, multiply: 3)
            XCTFail("Expected invalid coin quantity to fail")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -1)
            XCTAssertEqual(message, "\u{6295}\u{5e01}\u{6570}\u{91cf}\u{65e0}\u{6548}")
        }
        XCTAssertTrue(recorder.requests.isEmpty)

        try await api.addVideoCoin(aid: 789, multiply: 2, selectLike: true)
        await fulfillment(of: [requestExpectation], timeout: 2)

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/web-interface/coin/add")
        XCTAssertEqual(
            formValues(in: request),
            [
                "aid": "789",
                "multiply": "2",
                "select_like": "1",
                "csrf": "csrf-value",
                "cross_domain": "true",
                "source": "web_normal",
                "ga": "1",
            ])
    }

    @MainActor
    func testFavoriteFoldersAndMutationBuildExpectedRequests() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "favorite requests captured")
        requestExpectation.expectedFulfillmentCount = 4
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            if request.url?.path == "/x/v3/fav/folder/created/list-all" {
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"list\":[{\"id\":7,\"title\":\"\u{9ed8}\u{8ba4}\u{6536}\u{85cf}\u{5939}\"}]}}"
                )
            }
            return Self.response(for: request, body: "{\"code\":0,\"data\":{}}")
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; bili_jct=csrf-value; DedeUserID=1001")
        let folders = try await api.fetchFavoriteFolders(for: 321)
        try await api.setVideoFavorite(aid: 321, favorited: true)
        try await api.setVideoFavorite(aid: 321, addFolderIDs: [9, 7], removeFolderIDs: [11, 7])

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(folders.map(\.id), [7])
        let requests = recorder.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[0].url?.path, "/x/v3/fav/folder/created/list-all")
        let folderQuery = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(requests[0].url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(Self.queryValues(in: folderQuery), ["up_mid": "1001", "type": "2", "rid": "321"])
        XCTAssertEqual(requests[1].url?.path, "/x/v3/fav/folder/created/list-all")
        let repeatedFolderQuery = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(requests[1].url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(Self.queryValues(in: repeatedFolderQuery), ["up_mid": "1001", "type": "2", "rid": "321"])
        XCTAssertEqual(
            formValues(in: requests[2]),
            [
                "rid": "321",
                "type": "2",
                "add_media_ids": "7",
                "del_media_ids": "",
                "csrf": "csrf-value",
                "platform": "web",
                "gaia_source": "web_normal",
                "ga": "1",
            ])
        XCTAssertEqual(
            formValues(in: requests[3]),
            [
                "rid": "321",
                "type": "2",
                "add_media_ids": "9",
                "del_media_ids": "11",
                "csrf": "csrf-value",
                "platform": "web",
                "gaia_source": "web_normal",
                "ga": "1",
            ])
    }

    @MainActor
    func testUploaderFollowWebMutationBuildsFormAndPropagatesAPIError() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "follow request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: "{\"code\":-400,\"message\":\"\u{5173}\u{6ce8}\u{5931}\u{8d25}\",\"data\":null}"
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; bili_jct=csrf-value; DedeUserID=1001")
        do {
            try await api.setUploaderFollowing(mid: 654, following: true)
            XCTFail("Expected follow API error")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -400)
            XCTAssertEqual(message, "\u{5173}\u{6ce8}\u{5931}\u{8d25}")
        }

        await fulfillment(of: [requestExpectation], timeout: 2)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/relation/modify")
        XCTAssertEqual(
            formValues(in: request),
            [
                "fid": "654",
                "act": "1",
                "re_src": "11",
                "csrf": "csrf-value",
                "gaia_source": "web_normal",
                "ga": "1",
            ])
    }

    @MainActor
    func testUploaderProfileRejectsInvalidMIDWithoutRequest() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            throw URLError(.badServerResponse)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        for operation in [
            { try await api.fetchUploaderProfile(mid: 0) },
            { try await api.fetchUploaderStatsProfile(mid: -1) },
        ] {
            do {
                _ = try await operation()
                XCTFail("Expected invalid uploader UID to fail")
            } catch let error as BiliAPIError {
                guard case .api(let code, let message) = error else {
                    return XCTFail("Unexpected API error: \(error)")
                }
                XCTAssertEqual(code, -1)
                XCTAssertEqual(message, "UP \u{4e3b} UID \u{65e0}\u{6548}")
            }
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    @MainActor
    func testUploaderProfileMergesVisibleSourcesAndSurvivesPartialFailures() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            let query = Self.queryValues(for: request)
            switch (request.url?.host, request.url?.path) {
            case ("api.bilibili.com", "/x/web-interface/card"):
                return Self.response(
                    for: request,
                    body: "{\"code\":-500,\"message\":\"card failed\",\"data\":null}"
                )
            case ("app.bilibili.com", "/x/v2/space"):
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"card\":{\"mid\":123,\"name\":\"\u{6d4b}\u{8bd5}UP\",\"fans\":200}}}"
                )
            case ("api.bilibili.com", "/x/web-interface/nav"):
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"wbi_img\":{"
                        + "\"img_url\":\"https://i0.hdslb.com/bfs/wbi/abcdef.png\","
                        + "\"sub_url\":\"https://i0.hdslb.com/bfs/wbi/ghijkl.png\"}}}"
                )
            case ("api.bilibili.com", "/x/space/wbi/acc/info"):
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"follower\":300}}"
                )
            case ("api.bilibili.com", "/x/relation/stat"):
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"following\":12,\"follower\":400}}"
                )
            case ("api.bilibili.com", "/x/space/upstat"):
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"likes\":999,\"archive\":{\"count\":88}}}"
                )
            case ("api.bilibili.com", "/x/relation"):
                XCTAssertEqual(query["fid"], "123")
                return Self.response(for: request, body: "{\"code\":0,\"data\":{\"attribute\":2}}")
            case ("space.bilibili.com", "/123"):
                return Self.response(
                    for: request,
                    body: "window.__INITIAL_STATE__={\"card\":{\"mid\":123,\"fans\":500}};"
                )
            default:
                throw URLError(.badServerResponse)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let profile = try await api.fetchUploaderProfile(mid: 123)

        XCTAssertEqual(profile.card?.name, "\u{6d4b}\u{8bd5}UP")
        XCTAssertEqual(profile.visibleFollowerCount, 400)
        XCTAssertEqual(profile.visibleFollowingCount, 12)
        XCTAssertEqual(profile.visibleLikeCount, 999)
        XCTAssertEqual(profile.visibleArchiveCount, 88)
        XCTAssertTrue(recorder.requests.contains { $0.url?.path == "/x/web-interface/card" })
        XCTAssertTrue(recorder.requests.contains { $0.url?.path == "/x/v2/space" })
    }

    @MainActor
    func testUploaderProfileFallsBackToAppAccessKeyForViewerRelation() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch (request.url?.host, request.url?.path) {
            case ("api.bilibili.com", "/x/web-interface/card"):
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"card\":{\"mid\":123,\"name\":\"\u{6d4b}\u{8bd5}UP\"}}}"
                )
            case ("app.bilibili.com", "/x/v2/space"):
                return Self.response(
                    for: request,
                    body: "{\"code\":0,\"data\":{\"card\":{\"mid\":123,\"name\":\"\u{6d4b}\u{8bd5}UP\"}}}"
                )
            case ("api.bilibili.com", "/x/relation"):
                let query = Self.queryValues(for: request)
                if query["access_key"] == "app-access-key" {
                    return Self.response(for: request, body: "{\"code\":0,\"data\":{\"attribute\":2}}")
                }
                return Self.response(
                    for: request,
                    body: "{\"code\":-101,\"message\":\"cookie failed\",\"data\":null}"
                )
            default:
                return Self.response(for: request, body: "{\"code\":0,\"data\":null}")
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            accessKey: "app-access-key"
        )
        let profile = try await api.fetchUploaderProfile(mid: 123)

        XCTAssertEqual(profile.following, true)
        let relationRequests = recorder.requests.filter { $0.url?.path == "/x/relation" }
        XCTAssertTrue(relationRequests.contains { Self.queryValues(for: $0)["access_key"] == nil })
        XCTAssertTrue(relationRequests.contains { Self.queryValues(for: $0)["access_key"] == "app-access-key" })
    }

    @MainActor
    func testUploaderWebVideoPageBuildsSignedRequestAndDecodesPagination() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch request.url?.path {
            case "/x/web-interface/nav":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/abcdef.png","sub_url":"https://i0.hdslb.com/bfs/wbi/ghijkl.png"}}}
                        """
                )
            case "/x/space/wbi/arc/search":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"list":{"vlist":[{"bvid":"BV1test123","aid":101,"author":"\u{6d4b}\u{8bd5}UP","mid":321,"title":"\u{6d4b}\u{8bd5}\u{6295}\u{7a3f}","length":"01:02"}]},"page":{"count":61}}}
                        """
                )
            default:
                throw URLError(.badServerResponse)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let result = try await api.fetchUploaderVideoPage(mid: 321, page: 2, order: .pubdate)

        XCTAssertEqual(result.videos.map(\.bvid), ["BV1test123"])
        XCTAssertEqual(result.totalCount, 61)
        XCTAssertTrue(result.hasMore)
        XCTAssertEqual(result.nextCursor, UploaderVideoPageCursor(aid: "101", next: nil))

        let request = try XCTUnwrap(recorder.requests.last)
        XCTAssertEqual(request.url?.path, "/x/space/wbi/arc/search")
        let query = Self.queryValues(for: request)
        XCTAssertEqual(query["mid"], "321")
        XCTAssertEqual(query["pn"], "2")
        XCTAssertEqual(query["ps"], "30")
        XCTAssertEqual(query["order"], UploaderVideoOrder.pubdate.rawValue)
        XCTAssertEqual(query["platform"], "web")
        XCTAssertEqual(query["web_location"], "333.1387")
        XCTAssertEqual(query["order_avoided"], "true")
        XCTAssertNotNil(query["wts"])
        XCTAssertNotNil(query["w_rid"])
    }

    @MainActor
    func testUploaderVideoPageFallsBackToSignedAppArchiveWithCursor() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch request.url?.path {
            case "/x/web-interface/nav":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/abcdef.png","sub_url":"https://i0.hdslb.com/bfs/wbi/ghijkl.png"}}}
                        """
                )
            case "/x/space/wbi/arc/search":
                return Self.response(for: request, body: "{\"code\":-352,\"message\":\"web failed\",\"data\":null}")
            case "/x/v2/space/archive/cursor":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"count":42,"has_next":true,"next":77,"item":[{"bvid":"BV1fallback","param":"456","title":"App \u{6295}\u{7a3f}","author":"\u{6d4b}\u{8bd5}UP"}]}}
                        """
                )
            default:
                throw URLError(.badServerResponse)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let result = try await api.fetchUploaderVideoPage(
            mid: 321,
            cursor: UploaderVideoPageCursor(aid: "123", next: 45),
            order: .click
        )

        XCTAssertEqual(result.videos.map(\.bvid), ["BV1fallback"])
        XCTAssertEqual(result.totalCount, 42)
        XCTAssertTrue(result.hasMore)
        XCTAssertEqual(result.nextCursor, UploaderVideoPageCursor(aid: "456", next: 77))

        let appRequest = try XCTUnwrap(
            recorder.requests.first { $0.url?.path == "/x/v2/space/archive/cursor" }
        )
        let query = Self.queryValues(for: appRequest)
        XCTAssertEqual(appRequest.url?.host, "app.bilibili.com")
        XCTAssertEqual(query["vmid"], "321")
        XCTAssertEqual(query["aid"], "123")
        XCTAssertEqual(query["next"], "45")
        XCTAssertEqual(query["order"], UploaderVideoOrder.click.rawValue)
        XCTAssertNotNil(query["appkey"])
        XCTAssertNotNil(query["ts"])
        XCTAssertNotNil(query["sign"])
    }

    @MainActor
    func testUploaderSeasonSeriesBuildsRequestAndDecodesItems() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"items_lists":{"page":{"page_num":2,"page_size":5,"total":9},"seasons_list":[{"meta":{"season_id":11,"name":"\u{6d4b}\u{8bd5}\u{5408}\u{96c6}"}}],"series_list":[{"meta":{"series_id":12,"name":"\u{6d4b}\u{8bd5}\u{5217}\u{8868}"}}]}}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "")
        let result = try await api.fetchUploaderSeasonSeries(mid: 321, page: 2, pageSize: 5)

        XCTAssertEqual(result.page?.total, 9)
        XCTAssertEqual(result.items.map(\.title), ["\u{6d4b}\u{8bd5}\u{5408}\u{96c6}", "\u{6d4b}\u{8bd5}\u{5217}\u{8868}"])
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/polymer/web-space/seasons_series_list")
        XCTAssertEqual(
            Self.queryValues(for: request),
            ["mid": "321", "page_num": "2", "page_size": "5"]
        )
    }

    @MainActor
    func testUploaderSeasonAndSeriesArchivePagesPreservePathsSortAndPagination() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch request.url?.path {
            case "/x/polymer/web-space/seasons_archives_list":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"archives":[{"aid":101,"bvid":"BV1season","title":"\u{5408}\u{96c6}\u{6295}\u{7a3f}"}],"page":{"page_num":2,"page_size":30,"total":61}}}
                        """
                )
            case "/x/series/archives":
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"archives":[{"aid":102,"bvid":"BV1series","title":"\u{5217}\u{8868}\u{6295}\u{7a3f}"}],"page":{"page_num":2,"page_size":20,"total":40}}}
                        """
                )
            default:
                throw URLError(.badServerResponse)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "")
        let owner = VideoOwner(mid: 321, name: "\u{6d4b}\u{8bd5}UP", face: nil)
        let season = try await api.fetchUploaderSeasonSeriesArchivePage(
            mid: 321,
            owner: owner,
            kind: .season(11),
            page: 2,
            pageSize: 30,
            sort: .asc
        )
        let series = try await api.fetchUploaderSeasonSeriesArchivePage(
            mid: 321,
            owner: owner,
            kind: .series(12),
            page: 2,
            pageSize: 20,
            sort: .desc
        )

        XCTAssertEqual(season.videos.map(\.bvid), ["BV1season"])
        XCTAssertEqual(season.totalCount, 61)
        XCTAssertTrue(season.hasMore)
        XCTAssertEqual(series.videos.map(\.bvid), ["BV1series"])
        XCTAssertEqual(series.totalCount, 40)
        XCTAssertFalse(series.hasMore)

        let seasonRequest = try XCTUnwrap(
            recorder.requests.first { $0.url?.path == "/x/polymer/web-space/seasons_archives_list" }
        )
        XCTAssertEqual(
            Self.queryValues(for: seasonRequest),
            [
                "mid": "321",
                "season_id": "11",
                "sort_reverse": "true",
                "page_size": "30",
                "page_num": "2",
                "web_location": "333.1387",
            ]
        )
        let seriesRequest = try XCTUnwrap(
            recorder.requests.first { $0.url?.path == "/x/series/archives" }
        )
        XCTAssertEqual(
            Self.queryValues(for: seriesRequest),
            [
                "mid": "321",
                "series_id": "12",
                "sort": "desc",
                "ps": "20",
                "pn": "2",
                "web_location": "333.1387",
            ]
        )
    }

    @MainActor
    func testUploaderSeasonSeriesRejectsInvalidMIDAndMissingPayload() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, body: "{\"code\":0,\"data\":null}")
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "")
        let owner = VideoOwner(mid: 321, name: "\u{6d4b}\u{8bd5}UP", face: nil)
        do {
            _ = try await api.fetchUploaderSeasonSeries(mid: 0)
            XCTFail("Expected invalid uploader UID to fail")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -1)
            XCTAssertEqual(message, "UP \u{4e3b} UID \u{65e0}\u{6548}")
        }
        do {
            _ = try await api.fetchUploaderSeasonSeriesArchivePage(
                mid: -1,
                owner: owner,
                kind: .season(11)
            )
            XCTFail("Expected invalid uploader UID to fail")
        } catch let error as BiliAPIError {
            guard case .api(let code, let message) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(code, -1)
            XCTAssertEqual(message, "UP \u{4e3b} UID \u{65e0}\u{6548}")
        }
        XCTAssertTrue(recorder.requests.isEmpty)

        do {
            _ = try await api.fetchUploaderSeasonSeries(mid: 321)
            XCTFail("Expected missing payload to fail")
        } catch let error as BiliAPIError {
            guard case .missingPayload = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
        }
        XCTAssertEqual(recorder.request?.url?.path, "/x/polymer/web-space/seasons_series_list")
    }

    @MainActor
    func testWebAndAppQRCodeLoginBuildExpectedRequests() async throws {
        let requestExpectation = expectation(description: "QR login requests captured")
        requestExpectation.expectedFulfillmentCount = 4
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            switch request.url?.path {
            case "/x/passport-login/web/qrcode/generate":
                return Self.response(
                    for: request,
                    body: #"{"code":0,"data":{"url":"https://example.com/web-qr","qrcode_key":"web-key"}}"#
                )
            case "/x/passport-tv-login/qrcode/auth_code":
                return Self.response(
                    for: request,
                    body: #"{"code":0,"data":{"auth_code":"app-key","url":"https://example.com/app-qr"}}"#
                )
            case "/x/passport-tv-login/qrcode/poll":
                return Self.response(for: request, body: #"{"code":86090,"message":"\#u{5df2}\#u{626b}\#u{7801}"}"#)
            case "/x/passport-login/web/qrcode/poll":
                return Self.response(
                    for: request,
                    body: #"{"code":0,"data":{"code":86101,"message":"\#u{672a}\#u{626b}\#u{7801}"}}"#
                )
            default:
                throw URLError(.badServerResponse)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "buvid3=test-buvid")
        let webQR = try await api.generateQRCodeLogin()
        let appQR = try await api.generateAppQRCodeLogin()
        let webPoll = try await api.pollQRCodeLogin(qrcodeKey: webQR.qrcodeKey)
        let appPoll = try await api.pollAppQRCodeLogin(authCode: appQR.qrcodeKey)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(webQR.qrcodeKey, "web-key")
        XCTAssertEqual(appQR.qrcodeKey, "app-key")
        XCTAssertEqual(webPoll.data.status, .waitingForScan)
        XCTAssertEqual(appPoll.status, .waitingForConfirm)

        let webRequest = try XCTUnwrap(
            recorder.requests.first { $0.url?.path == "/x/passport-login/web/qrcode/generate" }
        )
        XCTAssertEqual(webRequest.httpMethod, "GET")
        XCTAssertEqual(webRequest.value(forHTTPHeaderField: "Referer"), "https://passport.bilibili.com/login")

        let webPollRequest = try XCTUnwrap(
            recorder.requests.first { $0.url?.path == "/x/passport-login/web/qrcode/poll" }
        )
        XCTAssertEqual(webPollRequest.httpMethod, "GET")
        XCTAssertEqual(Self.queryValues(for: webPollRequest)["qrcode_key"], "web-key")

        for path in [
            "/x/passport-tv-login/qrcode/auth_code",
            "/x/passport-tv-login/qrcode/poll",
        ] {
            let request = try XCTUnwrap(recorder.requests.first { $0.url?.path == path })
            let values = Self.queryValues(for: request)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=utf-8")
            XCTAssertEqual(values["appkey"], "4409e2ce8ffd12b8")
            XCTAssertFalse((values["sign"] ?? "").isEmpty)
            XCTAssertFalse((values["ts"] ?? "").isEmpty)
        }

        let appQRRequest = try XCTUnwrap(
            recorder.requests.first { $0.url?.path == "/x/passport-tv-login/qrcode/auth_code" }
        )
        XCTAssertEqual(Self.queryValues(for: appQRRequest)["local_id"], "0")
        let appPollRequest = try XCTUnwrap(
            recorder.requests.first { $0.url?.path == "/x/passport-tv-login/qrcode/poll" }
        )
        XCTAssertEqual(Self.queryValues(for: appPollRequest)["auth_code"], "app-key")
    }

    @MainActor
    func testAppSMSCodeBuildsSignedFormRequest() async throws {
        let requestExpectation = expectation(description: "SMS request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(for: request, body: #"{"code":0,"data":{"captcha_key":"captcha-key"}}"#)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "buvid3=test-buvid")
        let result = try await api.sendAppSMSCode(phone: "13800138000", countryCode: "852")

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(result.captchaKey, "captcha-key")
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/passport-login/sms/send")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=utf-8")
        let requestBuvid = cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["buvid3"]
        XCTAssertFalse((requestBuvid ?? "").isEmpty)
        let values = formValues(in: request)
        XCTAssertEqual(values["appkey"], "dfca71928277209b")
        XCTAssertEqual(values["buvid"], requestBuvid)
        XCTAssertEqual(values["cid"], "852")
        XCTAssertEqual(values["local_id"], requestBuvid)
        XCTAssertEqual(values["tel"], "13800138000")
        XCTAssertFalse((values["login_session_id"] ?? "").isEmpty)
        XCTAssertFalse((values["sign"] ?? "").isEmpty)
        XCTAssertFalse((values["ts"] ?? "").isEmpty)
    }

    @MainActor
    func testFetchNavUserCoalescesConcurrentRequests() async throws {
        let firstRequestExpectation = expectation(description: "first nav request captured")
        let responseRelease = DispatchSemaphore(value: 0)
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            firstRequestExpectation.fulfill()
            _ = responseRelease.wait(timeout: .now() + 2)
            return Self.response(
                for: request,
                body: #"{"code":0,"data":{"isLogin":true,"uname":"\#u{6d4b}\#u{8bd5}\#u{7528}\#u{6237}","mid":1001}}"#
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let firstTask = Task { try await api.fetchNavUser() }
        await fulfillment(of: [firstRequestExpectation], timeout: 2)
        let secondTask = Task { try await api.fetchNavUser() }
        try await Task.sleep(for: .milliseconds(50))
        responseRelease.signal()

        let firstUser = try await firstTask.value
        let secondUser = try await secondTask.value

        XCTAssertEqual(firstUser.mid, 1001)
        XCTAssertEqual(secondUser.mid, 1001)
        XCTAssertEqual(recorder.requests.map(\.url?.path), ["/x/web-interface/nav"])
    }

    @MainActor
    func testFetchWBIKeysCoalescesConcurrentRequests() async throws {
        let firstRequestExpectation = expectation(description: "first WBI request captured")
        let responseRelease = DispatchSemaphore(value: 0)
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            firstRequestExpectation.fulfill()
            _ = responseRelease.wait(timeout: .now() + 2)
            return Self.response(
                for: request,
                body:
                    #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
            )
        }
        defer {
            responseRelease.signal()
            RequestContractURLProtocol.reset()
        }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        await api.state.clearWBIKeys()
        let first = Task { try await api.fetchWBIKeys() }
        await fulfillment(of: [firstRequestExpectation], timeout: 2)
        let second = Task { try await api.fetchWBIKeys() }
        try await Task.sleep(for: .milliseconds(20))
        responseRelease.signal()

        let keys = try await [first.value, second.value]

        XCTAssertEqual(keys.map(\.imgKey), ["abc", "abc"])
        XCTAssertEqual(keys.map(\.subKey), ["def", "def"])
        XCTAssertEqual(recorder.requests.map(\.url?.path), ["/x/web-interface/nav"])
    }

    @MainActor
    func testFetchPgcSeasonInfoPrefersEpisodeThenFallsBackToSeason() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "PGC season requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            if Self.queryValue(named: "ep_id", in: request) == "42" {
                return Self.response(
                    for: request,
                    body: #"{"code":-404,"message":"episode not found","result":null}"#
                )
            }
            return Self.response(
                for: request,
                body: #"{"code":0,"result":{"season_id":120,"title":"PGC fallback"}}"#
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let season = try await api.fetchPgcSeasonInfo(seasonID: 120, epID: 42)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(season.seasonID, 120)
        let requests = recorder.requests.filter { $0.url?.path == "/pgc/view/web/season" }
        XCTAssertEqual(requests.count, 2)
        let requestsByParameter = Dictionary(
            uniqueKeysWithValues: requests.compactMap { request in
                let query = Self.queryValues(for: request)
                if let epID = query["ep_id"] {
                    return ("ep_id", (epID, request))
                }
                if let seasonID = query["season_id"] {
                    return ("season_id", (seasonID, request))
                }
                return nil
            }
        )
        XCTAssertEqual(requestsByParameter["ep_id"]?.0, "42")
        XCTAssertEqual(requestsByParameter["season_id"]?.0, "120")
        XCTAssertEqual(
            requestsByParameter["ep_id"]?.1.value(forHTTPHeaderField: "Referer"),
            "https://www.bilibili.com/bangumi/play/ep42"
        )
        XCTAssertEqual(
            requestsByParameter["season_id"]?.1.value(forHTTPHeaderField: "Referer"),
            "https://www.bilibili.com/bangumi/play/ss120"
        )
    }

    @MainActor
    func testFetchPgcPlayURLBuildsSignedTargetQualityRequestAndDecodesDASH() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let defaults = UserDefaults.standard
        let previousPreference = defaults.object(forKey: VideoCodecPreference.storageKey)
        defaults.set(VideoCodecPreference.forceH264.rawValue, forKey: VideoCodecPreference.storageKey)
        defer {
            if let previousPreference {
                defaults.set(previousPreference, forKey: VideoCodecPreference.storageKey)
            } else {
                defaults.removeObject(forKey: VideoCodecPreference.storageKey)
            }
            RequestContractURLProtocol.reset()
        }

        let requestExpectation = expectation(description: "PGC signed play URL request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body:
                    #"{"code":0,"result":{"video_info":{"code":0,"quality":80,"accept_quality":[80],"dash":{"video":[{"id":80,"base_url":"https://video.example.com/video.m4s","codecs":"avc1.640028","codecid":7,"mime_type":"video/mp4"}],"audio":[{"id":30280,"base_url":"https://audio.example.com/audio.m4s","codecs":"mp4a.40.2","mime_type":"audio/mp4"}]}}}}"#
            )
        }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let data = try await api.fetchPgcPlayURL(
            bvid: "BV1PGCtest",
            cid: 24680,
            seasonID: 120,
            epID: 42,
            preferredQuality: 80
        )

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(data.quality, 80)
        XCTAssertEqual(data.dash?.video?.first?.id, 80)
        XCTAssertEqual(data.dash?.bestAudioStream?.id, 30280)
        let request = try XCTUnwrap(
            recorder.requests.first(where: { $0.url?.path == "/pgc/player/web/v2/playurl" })
        )
        let query = Self.queryValues(for: request)
        XCTAssertEqual(query["bvid"], "BV1PGCtest")
        XCTAssertEqual(query["cid"], "24680")
        XCTAssertEqual(query["season_id"], "120")
        XCTAssertEqual(query["ep_id"], "42")
        XCTAssertEqual(query["qn"], "80")
        XCTAssertEqual(query["fnval"], "4048")
        XCTAssertEqual(query["platform"], "iphone")
        XCTAssertEqual(query["video_codecid"], "7")
        XCTAssertNotNil(query["w_rid"])
        XCTAssertNotNil(query["wts"])
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Referer"),
            "https://www.bilibili.com/bangumi/play/ep42"
        )
    }

    @MainActor
    func testFetchPgcPlayURLPropagatesMissingPayload() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let defaults = UserDefaults.standard
        let previousPreference = defaults.object(forKey: VideoCodecPreference.storageKey)
        defaults.set(VideoCodecPreference.forceH264.rawValue, forKey: VideoCodecPreference.storageKey)
        defer {
            if let previousPreference {
                defaults.set(previousPreference, forKey: VideoCodecPreference.storageKey)
            } else {
                defaults.removeObject(forKey: VideoCodecPreference.storageKey)
            }
            RequestContractURLProtocol.reset()
        }

        let requestExpectation = expectation(description: "PGC missing payload request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            requestExpectation.fulfill()
            return Self.response(for: request, body: #"{"code":0,"result":{}}"#)
        }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        do {
            _ = try await api.fetchPgcPlayURL(
                bvid: "BV1PGCtest",
                cid: 24680,
                seasonID: 120,
                epID: 42,
                preferredQuality: 80
            )
            XCTFail("Expected missing PGC play URL payload")
        } catch let error as BiliAPIError {
            guard case .missingPayload = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
        }

        await fulfillment(of: [requestExpectation], timeout: 2)
        XCTAssertNotNil(
            recorder.requests.first(where: { $0.url?.path == "/pgc/player/web/v2/playurl" })
        )
    }

    @MainActor
    func testFetchPlayURLUsesPreferredQualityBuildsSignedRequestAndDecodesDASH() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let defaults = UserDefaults.standard
        let previousPreference = defaults.object(forKey: VideoCodecPreference.storageKey)
        defaults.set(VideoCodecPreference.forceH264.rawValue, forKey: VideoCodecPreference.storageKey)
        defer {
            if let previousPreference {
                defaults.set(previousPreference, forKey: VideoCodecPreference.storageKey)
            } else {
                defaults.removeObject(forKey: VideoCodecPreference.storageKey)
            }
            RequestContractURLProtocol.reset()
        }

        let requestExpectation = expectation(description: "video play URL request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            requestExpectation.fulfill()
            return Self.response(for: request, body: Self.playableDASHResponse(quality: 80))
        }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            playURLCache: PlayURLCache()
        )
        let data = try await api.fetchPlayURL(
            bvid: "BV1videoContract",
            cid: 24_680,
            qn: 112,
            preferredQuality: 80
        )

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(data.quality, 80)
        XCTAssertEqual(data.dash?.video?.first?.id, 80)
        XCTAssertEqual(data.dash?.bestAudioStream?.id, 30_280)
        let request = try XCTUnwrap(
            recorder.requests.first(where: { $0.url?.path == "/x/player/wbi/playurl" })
        )
        let query = Self.queryValues(for: request)
        XCTAssertEqual(query["bvid"], "BV1videoContract")
        XCTAssertEqual(query["cid"], "24680")
        XCTAssertEqual(query["qn"], "80")
        XCTAssertEqual(query["fnval"], "4048")
        XCTAssertEqual(query["video_codecid"], "7")
        XCTAssertNotNil(query["w_rid"])
        XCTAssertNotNil(query["wts"])
    }

    @MainActor
    func testFetchPlayURLReusesMemoryCacheForSameKey() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let defaults = UserDefaults.standard
        let previousPreference = defaults.object(forKey: VideoCodecPreference.storageKey)
        defaults.set(VideoCodecPreference.forceH264.rawValue, forKey: VideoCodecPreference.storageKey)
        defer {
            if let previousPreference {
                defaults.set(previousPreference, forKey: VideoCodecPreference.storageKey)
            } else {
                defaults.removeObject(forKey: VideoCodecPreference.storageKey)
            }
            RequestContractURLProtocol.reset()
        }

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            return Self.response(for: request, body: Self.playableDASHResponse(quality: 80))
        }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            playURLCache: PlayURLCache()
        )
        _ = try await api.fetchPlayURL(bvid: "BV1videoCache", cid: 24_681, preferredQuality: 80)
        _ = try await api.fetchPlayURL(bvid: "BV1videoCache", cid: 24_681, preferredQuality: 80)

        XCTAssertEqual(
            recorder.requests.filter { $0.url?.path == "/x/player/wbi/playurl" }.count,
            1
        )
    }

    @MainActor
    func testFetchPlayURLMergesConcurrentRequestsForSameKey() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let defaults = UserDefaults.standard
        let previousPreference = defaults.object(forKey: VideoCodecPreference.storageKey)
        defaults.set(VideoCodecPreference.forceH264.rawValue, forKey: VideoCodecPreference.storageKey)
        defer {
            if let previousPreference {
                defaults.set(previousPreference, forKey: VideoCodecPreference.storageKey)
            } else {
                defaults.removeObject(forKey: VideoCodecPreference.storageKey)
            }
            RequestContractURLProtocol.reset()
        }

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            Thread.sleep(forTimeInterval: 0.15)
            return Self.response(for: request, body: Self.playableDASHResponse(quality: 80))
        }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            playURLCache: PlayURLCache()
        )
        async let first = api.fetchPlayURL(bvid: "BV1videoPending", cid: 24_682, preferredQuality: 80)
        async let second = api.fetchPlayURL(bvid: "BV1videoPending", cid: 24_682, preferredQuality: 80)
        let results = try await [first, second]

        XCTAssertEqual(results.map(\.quality), [80, 80])
        XCTAssertEqual(
            recorder.requests.filter { $0.url?.path == "/x/player/wbi/playurl" }.count,
            1
        )
    }

    @MainActor
    func testFetchPlayURLDoesNotCoalesceDifferentPreferredQualityKeys() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let defaults = UserDefaults.standard
        let previousPreference = defaults.object(forKey: VideoCodecPreference.storageKey)
        defaults.set(VideoCodecPreference.forceH264.rawValue, forKey: VideoCodecPreference.storageKey)
        defer {
            if let previousPreference {
                defaults.set(previousPreference, forKey: VideoCodecPreference.storageKey)
            } else {
                defaults.removeObject(forKey: VideoCodecPreference.storageKey)
            }
            RequestContractURLProtocol.reset()
        }

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            let quality = Int(Self.queryValue(named: "qn", in: request) ?? "") ?? 80
            return Self.response(for: request, body: Self.playableDASHResponse(quality: quality))
        }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            playURLCache: PlayURLCache()
        )
        _ = try await api.fetchPlayURL(
            bvid: "BV1videoKeyIsolation",
            cid: 24_684,
            preferredQuality: 80
        )
        _ = try await api.fetchPlayURL(
            bvid: "BV1videoKeyIsolation",
            cid: 24_684,
            preferredQuality: 112
        )

        let playURLRequests = recorder.requests.filter { $0.url?.path == "/x/player/wbi/playurl" }
        XCTAssertEqual(playURLRequests.count, 2)
        XCTAssertEqual(
            Set(playURLRequests.compactMap { Self.queryValue(named: "qn", in: $0) }),
            ["80", "112"]
        )
    }

    @MainActor
    func testFetchWebPagePlayInfoUsesInjectedIncrementalJSON() async throws {
        let playInfoJSON = Self.playableDASHResponse(quality: 80)
        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            webPagePlayInfoStreamFetch: { _, _ in
                BiliWebPagePlayInfoStreamResult(
                    json: playInfoJSON,
                    fullPageData: nil,
                    receivedByteCount: 128,
                    expectedByteCount: 256,
                    elapsedMilliseconds: 1
                )
            }
        )

        let data = try await api.fetchWebPagePlayInfo(
            bvid: "BV1webpageIncremental",
            page: nil,
            referer: "https://www.bilibili.com/video/BV1webpageIncremental",
            cookieHeader: "SESSDATA=session-value"
        )

        XCTAssertEqual(data.quality, 80)
        XCTAssertEqual(data.dash?.video?.first?.id, 80)
    }

    @MainActor
    func testStartupRaceWaitsForWBIFailureBeforeReturningWebpageFallback() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let wbiStarted = expectation(description: "WBI request started")
        let webpageFinished = expectation(description: "webpage hedge finished")
        let releaseWBI = DispatchSemaphore(value: 0)
        let completion = RequestContractCompletionFlag()
        let recorder = RequestContractRecorder()
        let webpageJSON = Self.playableDASHResponse(quality: 80)

        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            if request.url?.path == "/x/player/wbi/playurl" {
                wbiStarted.fulfill()
                _ = releaseWBI.wait(timeout: .now() + 3)
                return Self.response(
                    for: request,
                    body: #"{"code":-352,"message":"risk control","data":null}"#
                )
            }
            return Self.response(for: request, body: #"{"code":-404,"message":"unexpected"}"#)
        }
        defer {
            releaseWBI.signal()
            RequestContractURLProtocol.reset()
        }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            playURLCache: PlayURLCache(),
            webPagePlayInfoStreamFetch: { _, _ in
                webpageFinished.fulfill()
                return BiliWebPagePlayInfoStreamResult(
                    json: webpageJSON,
                    fullPageData: nil,
                    receivedByteCount: 128,
                    expectedByteCount: 128,
                    elapsedMilliseconds: 1
                )
            }
        )
        let resultTask = Task {
            do {
                let result = try await api.fetchRacedStartupPlayURL(
                    bvid: "BV1startupDeferredFallback",
                    cid: 24_684,
                    page: nil,
                    requestedQuality: 80,
                    requestLease: nil,
                    requestSource: .preload
                )
                await completion.markCompleted()
                return result
            } catch {
                await completion.markCompleted()
                throw error
            }
        }

        await fulfillment(of: [wbiStarted, webpageFinished], timeout: 2)
        let completedBeforeWBIFailure = await completion.didComplete
        XCTAssertFalse(completedBeforeWBIFailure)
        releaseWBI.signal()

        let result = try await resultTask.value
        XCTAssertEqual(result?.data.quality, 80)
        let completedAfterWBIFailure = await completion.didComplete
        XCTAssertTrue(completedAfterWBIFailure)
        XCTAssertEqual(
            recorder.requests.filter { $0.url?.path == "/x/player/wbi/playurl" }.count,
            1
        )
    }

    @MainActor
    func testStartupPlayableFallbackDeadlineReturnsRaceCandidateWithoutCancellingSharedStage() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let bvid = "BV1deadline\(UUID().uuidString)"
        let playURLRequestCounter = RequestContractCounter()
        let webpageRequestCounter = RequestContractCounter()
        let slowWebpageGate = RequestContractAsyncGate()
        let lowerQualityResponse = Self.playableDASHResponse(
            quality: 80,
            acceptedQualities: [112, 80]
        )

        RequestContractURLProtocol.install { request in
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            guard request.url?.path == "/x/player/wbi/playurl" else {
                return Self.response(
                    for: request,
                    body: #"{"code":-404,"message":"unexpected"}"#
                )
            }
            guard playURLRequestCounter.increment() > 2 else {
                return Self.response(for: request, body: lowerQualityResponse)
            }
            return Self.response(
                for: request,
                body: #"{"code":-404,"message":"full fallback unavailable"}"#
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            playURLCache: PlayURLCache(),
            webPagePlayInfoStreamFetch: { _, _ in
                if webpageRequestCounter.increment() == 1 {
                    try await Task.sleep(nanoseconds: 50_000_000)
                    return BiliWebPagePlayInfoStreamResult(
                        json: lowerQualityResponse,
                        fullPageData: nil,
                        receivedByteCount: lowerQualityResponse.utf8.count,
                        expectedByteCount: Int64(lowerQualityResponse.utf8.count),
                        elapsedMilliseconds: 50
                    )
                }
                await slowWebpageGate.wait()
                throw URLError(.timedOut)
            }
        )
        api.libraryStore.setPlaybackPlayableFallbackDeadlineExperimentEnabled(true)

        let start = CFAbsoluteTimeGetCurrent()
        let data = try await api.fetchStartupPlayURL(
            bvid: bvid,
            cid: 24_685,
            preferredQuality: 112,
            requestSource: StartupPlayURLRequestSource.preload
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertEqual(data.quality, 80)
        XCTAssertEqual(data.dash?.video?.first?.id, 80)
        XCTAssertGreaterThanOrEqual(elapsed, 0.55)
        // Hosted simulators can delay executor scheduling beyond a wall-clock
        // ceiling. Below, assert the deadline outcome and that the unfinished
        // shared stage is still waiting; these verify the timeout contract.
        XCTAssertGreaterThanOrEqual(playURLRequestCounter.currentValue, 3)
        XCTAssertGreaterThanOrEqual(webpageRequestCounter.currentValue, 2)
        let sharedStageRemainedInFlight = await slowWebpageGate.isWaiting
        let context = await api.playbackAPIRequestContext()
        let sharedStageKey = BiliAPIClient.playURLFailureCacheKey(
            stage: "webpagePlayInfo",
            bvid: bvid,
            cid: 24_685,
            qn: 112,
            cookieMode: "auth-webpage-\(context.playbackStreamSourcePreference.cachePlatform)",
            credentialVersion: context.playbackCredentialVersion
        )
        let pendingSharedStageTask = await api.state.playURLStageTask(for: sharedStageKey)?.task
        let sharedStageTask = try XCTUnwrap(pendingSharedStageTask)
        await slowWebpageGate.release()
        XCTAssertTrue(sharedStageRemainedInFlight)
        guard case .failure(let sharedStageError) = await sharedStageTask.result else {
            return XCTFail("Expected the released shared webpage stage to fail")
        }
        XCTAssertFalse(sharedStageError is CancellationError)
        XCTAssertNotEqual((sharedStageError as? URLError)?.code, .cancelled)
        for _ in 0..<50 {
            guard await api.state.playURLStageTask(for: sharedStageKey) != nil else { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let remainingSharedStageTask = await api.state.playURLStageTask(for: sharedStageKey)
        XCTAssertNil(remainingSharedStageTask)

        let diagnostics = try await startupSchedulerDiagnostics(
            for: bvid,
            containing: "outcome=deadlineFallback"
        )
        XCTAssertTrue(diagnostics.contains("fullFallbackResult=deadline"))
        XCTAssertTrue(diagnostics.contains("fallbackDeadline=on"))
        XCTAssertTrue(diagnostics.contains("fallbackDeadlineBudget=650ms"))
    }

    @MainActor
    func testFetchWebPagePlayInfoRejectsNonzeroStreamWithoutValidFullPage() async throws {
        RequestContractURLProtocol.install { request in
            Self.response(for: request, body: "<html>no playinfo</html>")
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            webPagePlayInfoStreamFetch: { _, _ in
                BiliWebPagePlayInfoStreamResult(
                    json: nil,
                    fullPageData: nil,
                    receivedByteCount: 12,
                    expectedByteCount: nil,
                    elapsedMilliseconds: 1
                )
            }
        )

        do {
            _ = try await api.fetchWebPagePlayInfo(
                bvid: "BV1webpageMissing",
                page: nil,
                referer: "https://www.bilibili.com/video/BV1webpageMissing",
                cookieHeader: "SESSDATA=session-value"
            )
            XCTFail("Expected missing webpage playinfo payload")
        } catch let error as BiliAPIError {
            guard case .missingPayload = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
        }
    }

    @MainActor
    func testFetchWebPagePlayInfoRejectsZeroByteStreamAndFullPage() async throws {
        RequestContractURLProtocol.install { request in
            Self.response(for: request, data: Data())
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            webPagePlayInfoStreamFetch: { _, _ in
                BiliWebPagePlayInfoStreamResult(
                    json: nil,
                    fullPageData: nil,
                    receivedByteCount: 0,
                    expectedByteCount: nil,
                    elapsedMilliseconds: 1
                )
            }
        )

        do {
            _ = try await api.fetchWebPagePlayInfo(
                bvid: "BV1webpageEmpty",
                page: nil,
                referer: "https://www.bilibili.com/video/BV1webpageEmpty",
                cookieHeader: "SESSDATA=session-value"
            )
            XCTFail("Expected empty webpage response")
        } catch let error as BiliAPIError {
            guard case .emptyData = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
        }
    }

    @MainActor
    func testFetchWebPagePlayInfoFallsBackToFullPageAfterStreamError() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(
                for: request,
                body: "<script>window.__playinfo__=\(Self.playableDASHResponse(quality: 80));</script>"
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            webPagePlayInfoStreamFetch: { _, _ in throw URLError(.cannotConnectToHost) }
        )
        let data = try await api.fetchWebPagePlayInfo(
            bvid: "BV1webpageFullFallback",
            page: 2,
            referer: "https://www.bilibili.com/video/BV1webpageFullFallback",
            cookieHeader: "SESSDATA=session-value"
        )

        XCTAssertEqual(data.quality, 80)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.host, "www.bilibili.com")
        XCTAssertEqual(request.url?.path, "/video/BV1webpageFullFallback")
        XCTAssertEqual(Self.queryValue(named: "p", in: request), "2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "SESSDATA=session-value")
    }

    @MainActor
    func testFetchPopularVideosBuildsPagedRequestAndDecodesItems() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let requestExpectation = expectation(description: "popular videos request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: #"{"code":0,"data":{"list":[{"bvid":"BV1popular","aid":1001,"title":"\#u{70ed}\#u{95e8}\#u{89c6}\#u{9891}"}]}}"#
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let videos = try await api.fetchPopularVideos(page: 3)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(videos.map(\.bvid), ["BV1popular"])
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/web-interface/popular")
        XCTAssertEqual(Self.queryValues(for: request), ["pn": "3", "ps": "20"])
    }

    @MainActor
    func testFetchVideoDetailBVIDCoalescesConcurrentRequests() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let recorder = RequestContractRecorder()
        let firstRequestStarted = expectation(description: "first video detail request started")
        let secondCallStarted = expectation(description: "second video detail call started")
        let responseGate = DispatchSemaphore(value: 0)
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/view" {
                firstRequestStarted.fulfill()
                _ = responseGate.wait(timeout: .now() + 5)
            }
            return Self.response(
                for: request,
                body: Self.videoItemResponse(bvid: "BV1detail", aid: 1002)
            )
        }
        defer {
            responseGate.signal()
            RequestContractURLProtocol.reset()
        }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let first = Task { try await api.fetchVideoDetail(bvid: "BV1detail") }
        await fulfillment(of: [firstRequestStarted], timeout: 2)
        let second = Task {
            secondCallStarted.fulfill()
            return try await api.fetchVideoDetail(bvid: "BV1detail")
        }
        await fulfillment(of: [secondCallStarted], timeout: 2)
        try await Task.sleep(for: .milliseconds(20))
        responseGate.signal()
        let details = try await [first.value, second.value]

        XCTAssertEqual(details.map(\.bvid), ["BV1detail", "BV1detail"])
        let requests = recorder.requests.filter { $0.url?.path == "/x/web-interface/view" }
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(Self.queryValues(for: request), ["bvid": "BV1detail"])
        XCTAssertEqual(
            cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"],
            "session-value"
        )
    }

    @MainActor
    func testFetchVideoDetailAIDBuildsRequestAndDecodes() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let requestExpectation = expectation(description: "AID video detail request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: Self.videoItemResponse(bvid: "BV1aid", aid: 1003)
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let detail = try await api.fetchVideoDetail(aid: 1003)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(detail.bvid, "BV1aid")
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/web-interface/view")
        XCTAssertEqual(Self.queryValues(for: request), ["aid": "1003"])
    }

    @MainActor
    func testFetchVideoRelatedBuildsGuestScopedRequestAndDecodes() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let requestExpectation = expectation(description: "related videos request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: #"{"code":0,"data":[{"bvid":"BV1related","aid":1004,"title":"\#u{76f8}\#u{5173}\#u{63a8}\#u{8350}"}]}"#
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            guestModeEnabled: true
        )
        let videos = try await api.fetchVideoRelated(bvid: "BV1source")

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(videos.map(\.bvid), ["BV1related"])
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/web-interface/archive/related")
        XCTAssertEqual(
            Self.queryValues(for: request),
            ["bvid": "BV1source", "pn": "1", "ps": "40"]
        )
        let cookies = cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNotNil(cookies["buvid3"])
        XCTAssertNil(cookies["SESSDATA"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), BiliAPIClient.webUserAgent)
    }

    @MainActor
    func testFetchVideoShotNormalizesBVIDAndDecodesMetadata() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let requestExpectation = expectation(description: "video shot request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body:
                    #"{"code":0,"data":{"img_x_len":10,"img_y_len":10,"img_x_size":160,"img_y_size":90,"image":["https://image.example.com/shot.jpg"],"index":[0,10]}}"#
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let metadata = try await api.fetchVideoShot(bvid: " BV1shot ", cid: 1005)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertTrue(metadata.isUsable)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/player/videoshot")
        XCTAssertEqual(
            Self.queryValues(for: request),
            ["bvid": "BV1shot", "cid": "1005", "index": "1"]
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.bilibili.com/video/BV1shot")
        XCTAssertEqual(
            cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"],
            "session-value"
        )
    }

    @MainActor
    func testFetchDanmakuBuildsXMLRequestParsesAndUsesResourceCache() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        await SubtitleDanmakuResourceCache.shared.clear()

        let requestExpectation = expectation(description: "XML danmaku request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: #"<?xml version="1.0"?><i><d p="1.5,1,25,16777215,0,0,0,42">\#u{6d4b}\#u{8bd5}\#u{5f39}\#u{5e55}</d></i>"#
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let cid = 9_100_001
        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            guestModeEnabled: true
        )
        let first = try await api.fetchDanmaku(cid: cid)
        let second = try await api.fetchDanmaku(cid: cid)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(first.map(\.text), ["\u{6d4b}\u{8bd5}\u{5f39}\u{5e55}"])
        XCTAssertEqual(second, first)
        XCTAssertEqual(recorder.requests.count, 1)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.host, "comment.bilibili.com")
        XCTAssertEqual(request.url?.path, "/\(cid).xml")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.bilibili.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), BiliAPIClient.webUserAgent)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/xml,text/xml,*/*")
        XCTAssertEqual(request.cachePolicy, .returnCacheDataElseLoad)
        XCTAssertEqual(request.timeoutInterval, 8)
        let cookies = cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNotNil(cookies["buvid3"])
        XCTAssertNil(cookies["SESSDATA"])

        await SubtitleDanmakuResourceCache.shared.clear()
    }

    @MainActor
    func testFetchDanmakuSegmentNormalizesIndexBuildsProtobufRequestAndParses() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        await SubtitleDanmakuResourceCache.shared.clear()

        let requestExpectation = expectation(description: "protobuf danmaku request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(for: request, data: Self.protobufDanmakuSegmentData())
        }
        defer { RequestContractURLProtocol.reset() }

        let cid = 9_100_002
        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            guestModeEnabled: true
        )
        let items = try await api.fetchDanmakuSegment(cid: cid, segmentIndex: 0)
        let cachedItems = try await api.fetchDanmakuSegment(cid: cid, segmentIndex: 0)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(items.map(\.id), ["\(cid)-seg1-42"])
        XCTAssertEqual(items.map(\.text), ["\u{5206}\u{6bb5}\u{5f39}\u{5e55}"])
        XCTAssertEqual(items.first?.time, 1.5)
        XCTAssertEqual(cachedItems, items)
        XCTAssertEqual(recorder.requests.count, 1)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.host, "api.bilibili.com")
        XCTAssertEqual(request.url?.path, "/x/v2/dm/web/seg.so")
        XCTAssertEqual(
            Self.queryValues(for: request),
            ["type": "1", "oid": "\(cid)", "segment_index": "1"]
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.bilibili.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), BiliAPIClient.webUserAgent)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/octet-stream,*/*")
        XCTAssertEqual(request.cachePolicy, .returnCacheDataElseLoad)
        XCTAssertEqual(request.timeoutInterval, 8)
        let cookies = cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNotNil(cookies["buvid3"])
        XCTAssertNil(cookies["SESSDATA"])

        await SubtitleDanmakuResourceCache.shared.clear()
    }

    @MainActor
    func testFetchLiveRoomsBuildsAnonymousRequestAndDecodesFallbackRoomList() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "live recommendation request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"list":[{"roomid":31415,"title":"\u{76f4}\u{64ad}\u{6d4b}\u{8bd5}","uname":"\u{4e3b}\u{64ad}","live_status":1}]}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001; buvid3=live-guest-buvid"
        )
        let rooms = try await api.fetchLiveRooms(page: 3, refreshIndex: 7)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(rooms.map(\.roomID), [31_415])
        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.host, "api.live.bilibili.com")
        XCTAssertEqual(url.path, "/xlive/web-interface/v1/webMain/getMoreRecList")
        let query = Self.queryValues(in: components)
        XCTAssertEqual(query["platform"], "web")
        XCTAssertEqual(query["page"], "3")
        XCTAssertEqual(query["page_size"], "20")
        XCTAssertEqual(query["fresh_idx"], "7")
        XCTAssertEqual(query["fresh_type"], "3")
        XCTAssertNotNil(query["_"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://live.bilibili.com")
        XCTAssertEqual(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["buvid3"], "live-guest-buvid")
        XCTAssertNil(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"])
    }

    @MainActor
    func testFetchLiveRoomInfoBuildsRoomScopedRequestAndDecodes() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "live room info request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"room_id":24680,"uid":1001,"title":"\u{76f4}\u{64ad}\u{95f4}","live_status":1,"online":12}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let info = try await api.fetchLiveRoomInfo(roomID: 24_680)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(info.roomID, 24_680)
        XCTAssertEqual(info.title, "\u{76f4}\u{64ad}\u{95f4}")
        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.host, "api.live.bilibili.com")
        XCTAssertEqual(url.path, "/room/v1/Room/get_info")
        XCTAssertEqual(Self.queryValues(for: request), ["room_id": "24680"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://live.bilibili.com/24680")
    }

    @MainActor
    func testFetchLiveStreamInfoBuildsWebAndAndroidRequestsAndDecodesCandidate() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "web and android live play requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            let platform = Self.queryValue(named: "platform", in: request)
            if platform == "web" {
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"playurl_info":{"playurl":{"stream":[],"g_qn_desc":[{"qn":10000,"desc":"\u{539f}\u{753b}"}]}}}}
                        """
                )
            }
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"playurl_info":{"playurl":{"stream":[{"protocol_name":"http_hls","format":[{"format_name":"fmp4","codec":[{"codec_name":"avc","current_qn":10000,"accept_qn":[10000],"base_url":"/live.m3u8","url_info":[{"host":"https://live.example.com","extra":"?token=android"}]}]}]}],"g_qn_desc":[{"qn":10000,"desc":"\u{539f}\u{753b}"}]}}}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let result = try await api.fetchLiveStreamInfo(roomID: 13_579, quality: 10_000)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(
            result.candidates.map(\.url.absoluteString), ["https://live.example.com/live.m3u8?token=android"])
        XCTAssertEqual(result.playableQualities.map(\.qn), [10_000])
        let requests = recorder.requests.filter {
            $0.url?.path == "/xlive/web-room/v2/index/getRoomPlayInfo"
        }
        XCTAssertEqual(requests.count, 2)
        let queriesByPlatform = Dictionary(
            uniqueKeysWithValues: requests.compactMap { request in
                Self.queryValue(named: "platform", in: request).map { ($0, Self.queryValues(for: request)) }
            })
        XCTAssertEqual(queriesByPlatform["web"]?["room_id"], "13579")
        XCTAssertEqual(queriesByPlatform["web"]?["protocol"], "0,1")
        XCTAssertEqual(queriesByPlatform["web"]?["format"], "0,1,2")
        XCTAssertEqual(queriesByPlatform["web"]?["codec"], "0,1")
        XCTAssertEqual(queriesByPlatform["web"]?["qn"], "10000")
        XCTAssertEqual(queriesByPlatform["android"]?["room_id"], "13579")
        XCTAssertEqual(queriesByPlatform["android"]?["protocol"], "0,1")
        XCTAssertEqual(queriesByPlatform["android"]?["format"], "0,1,2")
        XCTAssertEqual(queriesByPlatform["android"]?["codec"], "0")
        XCTAssertEqual(queriesByPlatform["android"]?["qn"], "10000")
    }

    @MainActor
    func testFetchLiveDanmakuConnectionInfoUsesTransportSessionAndDecodesToken() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let requestExpectation = expectation(description: "live danmaku request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            guard request.url?.host == "api.live.bilibili.com" else {
                return Self.response(
                    for: request,
                    body: """
                        {"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}
                        """
                )
            }
            requestExpectation.fulfill()
            return Self.response(
                for: request,
                body: """
                    {"code":0,"data":{"token":"live-token","host_list":[{"host":"broadcast.example.com","wss_port":443}]}}
                    """
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestContractURLProtocol.self]
        configuration.urlCache = nil
        let transportSession = URLSession(configuration: configuration)
        let info = try await api.fetchLiveDanmakuConnectionInfo(
            roomID: 97531,
            cookieHeader: "SESSDATA=transport-session",
            transportSession: transportSession
        )

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(info.token, "live-token")
        XCTAssertEqual(info.hostList.first?.host, "broadcast.example.com")
        let request = try XCTUnwrap(
            recorder.requests.last(where: { $0.url?.host == "api.live.bilibili.com" })
        )
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.path, "/xlive/web-room/v1/index/getDanmuInfo")
        let query = Self.queryValues(for: request)
        XCTAssertEqual(query["id"], "97531")
        XCTAssertEqual(query["type"], "0")
        XCTAssertEqual(query["web_location"], "444.8")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "SESSDATA=transport-session")
    }

    @MainActor
    func testHomeRecommendWebBuildsSignedPaginationAndLimitRequest() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            return Self.response(for: request, body: #"{"code":0,"data":{"item":[]}}"#)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            recommendSource: .web
        )
        let videos = try await api.fetchRecommendFeed(freshIndex: 9, limit: 99)

        XCTAssertTrue(videos.isEmpty)
        let request = try XCTUnwrap(
            recorder.requests.first(where: { $0.url?.path == "/x/web-interface/wbi/index/top/feed/rcmd" })
        )
        let query = Self.queryValues(for: request)
        XCTAssertEqual(query["fresh_idx"], "9")
        XCTAssertEqual(query["brush"], "9")
        XCTAssertEqual(query["fresh_idx_1h"], "9")
        XCTAssertEqual(query["fresh_type"], "4")
        XCTAssertEqual(query["ps"], "50")
        XCTAssertNotNil(query["w_rid"])
        XCTAssertNotNil(query["wts"])
    }

    @MainActor
    func testHomeRecommendAppGuestFallsBackToWebWithoutAccessKey() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch request.url?.path {
            case "/x/v2/feed/index":
                return Self.response(for: request, body: #"{"code":0,"data":{"item":[]}}"#)
            case "/x/web-interface/nav":
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            default:
                return Self.response(for: request, body: #"{"code":0,"data":{"item":[]}}"#)
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            accessKey: "app-access-key",
            guestModeEnabled: true,
            recommendSource: .app
        )
        let videos = try await api.fetchRecommendFeed(freshIndex: 4, limit: 3)

        XCTAssertTrue(videos.isEmpty)
        let appRequests = recorder.requests.filter { $0.url?.path == "/x/v2/feed/index" }
        XCTAssertEqual(appRequests.count, 2)
        for request in appRequests {
            let query = Self.queryValues(for: request)
            XCTAssertEqual(query["idx"], "4")
            XCTAssertEqual(query["ps"], "3")
            XCTAssertEqual(query["page_size"], "3")
            XCTAssertEqual(query["login_event"], "0")
            XCTAssertNil(query["access_key"])
        }
        XCTAssertNotNil(
            recorder.requests.first(where: { $0.url?.path == "/x/web-interface/wbi/index/top/feed/rcmd" })
        )
    }

    @MainActor
    func testHomeRecommendAppReturnsPrimaryProfileResultWithoutWebFallback() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(
                for: request,
                body:
                    #"{"code":0,"data":{"item":[{"id":123,"bvid":"BV1HomeFeedTest","title":"\#u{63a8}\#u{8350}\#u{89c6}\#u{9891}","goto":"av","idx":12}]}}"#
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            accessKey: "app-access-key",
            recommendSource: .app
        )
        let videos = try await api.fetchRecommendFeed(freshIndex: 0, limit: 1)

        XCTAssertEqual(videos.map(\.bvid), ["BV1HomeFeedTest"])
        let appRequests = recorder.requests.filter { $0.url?.path == "/x/v2/feed/index" }
        XCTAssertEqual(appRequests.count, 1)
        XCTAssertEqual(Self.queryValues(for: try XCTUnwrap(appRequests.first))["access_key"], "app-access-key")
        XCTAssertNil(
            recorder.requests.first(where: { $0.url?.path == "/x/web-interface/wbi/index/top/feed/rcmd" })
        )
    }

    @MainActor
    func testHomeRecommendAppAPIErrorsFallBackToWeb() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch request.url?.path {
            case "/x/v2/feed/index":
                return Self.response(for: request, body: #"{"code":-500,"message":"app failed"}"#)
            case "/x/web-interface/nav":
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            default:
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"item":[{"id":456,"bvid":"BV1HomeFallback","title":"\#u{7f51}\#u{9875}\#u{515c}\#u{5e95}\#u{89c6}\#u{9891}","goto":"av"}]}}"#
                )
            }
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            accessKey: "app-access-key",
            recommendSource: .app
        )
        let videos = try await api.fetchRecommendFeed(freshIndex: 5, limit: 2)

        XCTAssertEqual(videos.map(\.bvid), ["BV1HomeFallback"])
        XCTAssertEqual(recorder.requests.filter { $0.url?.path == "/x/v2/feed/index" }.count, 2)
        XCTAssertEqual(
            recorder.requests.filter { $0.url?.path == "/x/web-interface/wbi/index/top/feed/rcmd" }.count,
            1
        )
    }

    @MainActor
    func testHomeRecommendCoalescesConcurrentIdenticalRequests() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            Thread.sleep(forTimeInterval: 0.15)
            return Self.response(for: request, body: #"{"code":0,"data":{"item":[]}}"#)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001", recommendSource: .web)
        async let first = api.fetchRecommendFeed(freshIndex: 6, limit: 8)
        async let second = api.fetchRecommendFeed(freshIndex: 6, limit: 8)
        let results = try await [first, second]

        XCTAssertEqual(results.map(\.count), [0, 0])
        XCTAssertEqual(
            recorder.requests.filter { $0.url?.path == "/x/web-interface/wbi/index/top/feed/rcmd" }.count,
            1
        )
    }

    @MainActor
    func testVideoHistoryReportsWebHeartbeatBodyAndReferer() async throws {
        let requestExpectation = expectation(description: "history heartbeat request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(for: request, body: #"{"code":0,"data":null}"#)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001; bili_jct=csrf-value; buvid3=buvid-value"
        )
        try await api.reportVideoHistory(
            aid: 123,
            cid: 456,
            progress: 12.9,
            duration: 300.8,
            bvid: "  BV1TEST  "
        )

        await fulfillment(of: [requestExpectation], timeout: 2)

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/click-interface/web/heartbeat")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.bilibili.com/video/BV1TEST")
        XCTAssertEqual(
            formValues(in: request),
            [
                "bvid": "BV1TEST",
                "cid": "456",
                "csrf": "csrf-value",
                "played_time": "12",
                "type": "3",
            ]
        )
        XCTAssertEqual(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"], "session-value")
    }

    @MainActor
    func testRequireCSRFReturnsMainAccountToken() async throws {
        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001; bili_jct=csrf-value"
        )

        let csrf = try await api.requireCSRF()
        XCTAssertEqual(csrf, "csrf-value")
    }

    @MainActor
    func testRequireCSRFRejectsLoggedOutSession() async throws {
        let api = try makeAPI(cookieHeader: "")

        do {
            _ = try await api.requireCSRF()
            XCTFail("Expected missing login credential")
        } catch let error as BiliAPIError {
            guard case .missingSESSDATA = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
        }
    }

    @MainActor
    func testRequireCSRFRejectsAuthenticatedSessionWithoutToken() async throws {
        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")

        do {
            _ = try await api.requireCSRF()
            XCTFail("Expected missing CSRF token")
        } catch let error as BiliAPIError {
            guard case .missingCSRF = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
        }
    }

    @MainActor
    func testVideoHistoryFallsBackFromHeartbeatToWebHistory() async throws {
        let requestExpectation = expectation(description: "history fallback requests captured")
        requestExpectation.expectedFulfillmentCount = 2
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            if request.url?.path == "/x/click-interface/web/heartbeat" {
                return Self.response(for: request, body: #"{"code":-1,"message":"heartbeat failed","data":null}"#)
            }
            return Self.response(for: request, body: #"{"code":0,"data":null}"#)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001; bili_jct=csrf-value")
        try await api.reportVideoHistory(aid: 123, cid: 456, progress: 42, duration: 120)

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(
            recorder.requests.map { $0.url?.path },
            [
                "/x/click-interface/web/heartbeat",
                "/x/v2/history/report",
            ])
        let request = try XCTUnwrap(recorder.requests.last)
        XCTAssertEqual(
            formValues(in: request),
            [
                "aid": "123",
                "cid": "456",
                "csrf": "csrf-value",
                "duration": "120",
                "ga": "1",
                "gaia_source": "web_normal",
                "progress": "42",
                "type": "3",
            ]
        )
    }

    @MainActor
    func testVideoHistoryUsesSignedAppAccessKeyRouteWhenWebCredentialIsUnavailable() async throws {
        let requestExpectation = expectation(description: "app history request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(for: request, body: #"{"code":0,"data":null}"#)
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001; buvid3=buvid-value",
            accessKey: "app-access-key"
        )
        try await api.reportVideoHistory(aid: 123, cid: 456, progress: 7, duration: 80)

        await fulfillment(of: [requestExpectation], timeout: 2)

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/v2/history/report")
        XCTAssertEqual(request.value(forHTTPHeaderField: "app-key"), "android")
        let fields = formValues(in: request)
        XCTAssertEqual(fields["access_key"], "app-access-key")
        XCTAssertEqual(fields["aid"], "123")
        XCTAssertEqual(fields["cid"], "456")
        XCTAssertEqual(fields["duration"], "80")
        XCTAssertEqual(fields["gaia_source"], "app_normal")
        XCTAssertEqual(fields["progress"], "7")
        XCTAssertEqual(fields["type"], "3")
        XCTAssertNotNil(fields["sign"])
        XCTAssertNotNil(fields["ts"])
    }

    @MainActor
    func testOfficialVideoListenPlaylistBuildsCursorQualityAndSortRequest() async throws {
        let requestExpectation = expectation(description: "official listen playlist request captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            let responseMessage = Data([0x10, 0x01, 0x18, 0x01])
            return Self.response(for: request, data: BiliListenerPlaylistCodec.frame(responseMessage))
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001; buvid3=buvid-value",
            accessKey: "app-access-key"
        )
        let page = try await api.fetchOfficialVideoListenPlaylist(
            aid: 123,
            cid: 456,
            cursor: "  cursor-token  ",
            sortOrder: .reverse
        )

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertTrue(page.reachedStart)
        XCTAssertTrue(page.reachedEnd)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.host, "app.bilibili.com")
        XCTAssertEqual(request.url?.path, BiliListenerPlaylistCodec.endpointPath)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "identify_v1 app-access-key")
        let expectedBody = try BiliListenerPlaylistCodec.encodeRequest(
            aid: 123,
            cid: 456,
            cursor: "cursor-token",
            sortOrder: .reverse
        )
        XCTAssertEqual(requestBodyData(from: request), BiliListenerPlaylistCodec.frame(expectedBody))
    }

    @MainActor
    func testOfficialVideoListenPlaylistRejectsInvalidAnchorBeforeRequest() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, data: Data())
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001", accessKey: "app-access-key")
        do {
            _ = try await api.fetchOfficialVideoListenPlaylist(aid: 123, cid: nil)
            XCTFail("Expected invalid anchor")
        } catch let error as BiliListenerPlaylistError {
            XCTAssertEqual(error, .invalidAnchor)
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    @MainActor
    func testOfficialVideoListenPlaylistRejectsMissingAccessKeyBeforeRequest() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, data: Data())
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(cookieHeader: "SESSDATA=session-value; DedeUserID=1001")
        do {
            _ = try await api.fetchOfficialVideoListenPlaylist(aid: 123, cid: 456)
            XCTFail("Expected missing access key")
        } catch let error as BiliListenerPlaylistError {
            XCTAssertEqual(error, .missingAccessKey)
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    @MainActor
    func testOfficialVideoListenPlaylistRejectsHTTPFailureAfterBuvidFallback() async throws {
        let requestExpectation = expectation(description: "official listen playlist HTTP failure captured")
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return Self.response(for: request, statusCode: 503, data: Data())
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001; buvid4=buvid4-value",
            accessKey: "app-access-key"
        )
        do {
            _ = try await api.fetchOfficialVideoListenPlaylist(aid: 123, cid: 456)
            XCTFail("Expected HTTP failure")
        } catch let error as BiliListenerPlaylistError {
            XCTAssertEqual(error, .invalidHTTPStatus(503))
        }

        await fulfillment(of: [requestExpectation], timeout: 2)
        XCTAssertFalse(recorder.request?.value(forHTTPHeaderField: "buvid")?.isEmpty ?? true)
    }

    @MainActor
    func testOfficialVideoListenPlaylistRejectsBiliStatus() async throws {
        RequestContractURLProtocol.install { request in
            Self.response(
                for: request,
                headerFields: [
                    "Content-Type": "application/grpc",
                    "bili-status-code": "7",
                    "bili-status-message": "permission%20denied",
                ],
                data: Data([0])
            )
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            accessKey: "app-access-key"
        )
        do {
            _ = try await api.fetchOfficialVideoListenPlaylist(aid: 123, cid: 456)
            XCTFail("Expected Bili status failure")
        } catch let error as BiliListenerPlaylistError {
            XCTAssertEqual(error, .grpcStatus(7, "permission denied"))
        }
    }

    @MainActor
    func testOfficialVideoListenPlaylistRejectsEmptyResponse() async throws {
        RequestContractURLProtocol.install { request in
            Self.response(for: request, data: Data())
        }
        defer { RequestContractURLProtocol.reset() }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            accessKey: "app-access-key"
        )
        do {
            _ = try await api.fetchOfficialVideoListenPlaylist(aid: 123, cid: 456)
            XCTFail("Expected invalid response")
        } catch let error as BiliListenerPlaylistError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    @MainActor
    func testRelatedStartupPackageWarmupJoinsPendingEarlyPlayURLPrefetch() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let preloadCenter = VideoPreloadCenter.shared
        await preloadCenter.clearPlayURLCache()
        let playURLStarted = expectation(description: "related play URL preload started")
        let playURLRequestCounter = RequestContractCounter()
        let responseGate = DispatchSemaphore(value: 0)
        let webpageGate = RequestContractAsyncGate()
        RequestContractURLProtocol.install { request in
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(
                    for: request,
                    body:
                        #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#
                )
            }
            if request.url?.path == "/x/player/wbi/playurl" {
                if playURLRequestCounter.increment() == 1 {
                    playURLStarted.fulfill()
                }
                _ = responseGate.wait(timeout: .now() + 2)
                return Self.response(for: request, body: Self.playableDASHResponse(quality: 80))
            }
            return Self.response(for: request, body: #"{"code":-404,"message":"unexpected"}"#)
        }
        defer {
            for _ in 0..<8 {
                responseGate.signal()
            }
            RequestContractURLProtocol.reset()
        }

        let api = try makeAPI(
            cookieHeader: "SESSDATA=session-value; DedeUserID=1001",
            playURLCache: PlayURLCache(),
            webPagePlayInfoStreamFetch: { _, _ in
                await webpageGate.wait()
                return BiliWebPagePlayInfoStreamResult(
                    json: Self.playableDASHResponse(quality: 80),
                    fullPageData: nil,
                    receivedByteCount: 128,
                    expectedByteCount: 128,
                    elapsedMilliseconds: 1
                )
            }
        )
        let video = VideoItem(
            bvid: "BV1relatedPending\(UUID().uuidString)",
            aid: 1,
            title: "Related pending preload",
            pic: nil,
            desc: nil,
            duration: 120,
            pubdate: nil,
            owner: nil,
            stat: nil,
            cid: 24_686,
            pages: nil,
            dimension: nil
        )

        let earlyDisposition = await preloadCenter.preloadRelatedPlayURLAfterFirstFrame(
            video,
            api: api,
            preferredQuality: 80
        )
        await fulfillment(of: [playURLStarted], timeout: 2)
        let warmupDisposition = await preloadCenter.preloadRelatedStartupPackageAfterFirstFrame(
            video,
            preferredQuality: 80
        )

        XCTAssertEqual(earlyDisposition, .started)
        XCTAssertEqual(warmupDisposition, .joined)

        for _ in 0..<8 {
            responseGate.signal()
        }
        await webpageGate.release()
        _ = await preloadCenter.pendingPlayURL(
            for: video.bvid,
            cid: 24_686,
            page: nil,
            preferredQuality: 80,
            maximumPendingWait: 2_000_000_000
        )
        await preloadCenter.cancelAll()
    }

    @MainActor
    func testWatchLaterMutationsUseExpectedScopeAndMatchingCredentials() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, body: #"{"code":0,"data":null}"#)
        }
        defer { RequestContractURLProtocol.reset() }
        let api = try makeAPI(cookieHeader: "SESSDATA=watch-session; DedeUserID=1001; bili_jct=watch-csrf")

        try await api.addToWatchLater(bvid: "BV1ToView0001")
        try await api.removeFromWatchLater(aids: [20, 10, 20, 0, -1])
        try await api.cleanWatchLater(.invalid)
        try await api.cleanWatchLater(.viewed)
        try await api.cleanWatchLater(.all)

        let requests = recorder.requests
        XCTAssertEqual(requests.count, 5)
        guard requests.count == 5 else { return }
        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/x/v2/history/toview/add", "/x/v2/history/toview/v2/dels",
            "/x/v2/history/toview/clear", "/x/v2/history/toview/clear", "/x/v2/history/toview/clear",
        ])
        let forms = requests.map { formValues(in: $0) }
        for (request, form) in zip(requests, forms) {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"], "watch-session")
            XCTAssertEqual(form["csrf"], "watch-csrf")
        }
        XCTAssertEqual(forms[0]["bvid"], "BV1ToView0001")
        XCTAssertEqual(forms[1]["resources"], "10,20")
        XCTAssertEqual(forms[2]["clean_type"], "1")
        XCTAssertEqual(forms[3]["clean_type"], "2")
        XCTAssertNil(forms[4]["clean_type"])
    }

    @MainActor
    func testWatchLaterMutationRejectsMissingCSRFBeforeSendingRequest() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, body: #"{"code":0}"#)
        }
        defer { RequestContractURLProtocol.reset() }
        let api = try makeAPI(cookieHeader: "SESSDATA=watch-session; DedeUserID=1001")

        do {
            try await api.cleanWatchLater(.all)
            XCTFail("Expected missing CSRF to reject the mutation")
        } catch let error as BiliAPIError {
            guard case .missingCSRF = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    @MainActor
    func testWatchLaterMutationDoesNotRetryAnAmbiguousTransportFailure() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            throw URLError(.networkConnectionLost)
        }
        defer { RequestContractURLProtocol.reset() }
        let api = try makeAPI(cookieHeader: "SESSDATA=watch-session; DedeUserID=1001; bili_jct=watch-csrf")

        do {
            try await api.removeFromWatchLater(aids: [10])
            XCTFail("Expected the network error to propagate")
        } catch {
            XCTAssertEqual(recorder.requests.count, 1)
        }
    }

    @MainActor
    func testSubtitleMetadataUsesWBIAndPlaybackAccountAndCDNDoesNotReceiveCookies() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch request.url?.path {
            case "/x/web-interface/nav":
                return Self.response(for: request, body: #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#)
            case "/x/player/wbi/v2":
                return Self.response(for: request, body: #"{"code":0,"data":{"subtitle":{"subtitles":[{"lan":"zh-CN","lan_doc":"\#u{4e2d}\#u{6587}","subtitle_url":"//aisubtitle.hdslb.com/test.json","type":0}]},"interaction":{"graph_version":12}}}"#)
            case "/test.json":
                return Self.response(for: request, body: #"{"body":[{"from":1,"to":3,"content":"\#u{5b57}\#u{5e55}"},{"from":5,"to":4,"content":"invalid"}]}"#)
            default: return Self.response(for: request, body: #"{"code":-404}"#)
            }
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=subtitle-session; DedeUserID=1001")
        let metadata = try await api.fetchPiliPlayerMetadata(bvid: "BV1test", cid: 123)
        let track = try XCTUnwrap(metadata.subtitle?.subtitles?.first)
        let cues = try await api.fetchPiliSubtitles(track)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(metadata.interaction?.graphVersion, 12)
        let metadataRequest = try XCTUnwrap(recorder.requests.first { $0.url?.path == "/x/player/wbi/v2" })
        let query = URLComponents(url: try XCTUnwrap(metadataRequest.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(query.contains { $0.name == "w_rid" })
        XCTAssertTrue(query.contains { $0.name == "cid" && $0.value == "123" })
        XCTAssertTrue(metadataRequest.value(forHTTPHeaderField: "Cookie")?.contains("subtitle-session") == true)
        let cdn = try XCTUnwrap(recorder.requests.first { $0.url?.path == "/test.json" })
        XCTAssertNil(cdn.value(forHTTPHeaderField: "Cookie"))
        XCTAssertFalse(cdn.httpShouldHandleCookies)
    }

    @MainActor
    func testInteractiveBranchRequestKeepsGraphAndDecodesDestinationCID() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, body: #"{"code":0,"data":{"edge_id":9,"title":"\#u{5f00}\#u{59cb}","edges":{"questions":[{"choices":[{"id":10,"cid":987,"option":"\#u{5411}\#u{5de6}"}]}]}}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=branch-session")
        let edge = try await api.fetchPiliInteractiveEdge(bvid: "BV1test", graphVersion: 321, edgeID: 9)
        XCTAssertEqual(edge.choices.first?.cid, 987)
        XCTAssertEqual(edge.choices.first?.id, 10)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/stein/edgeinfo_v2")
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(query.contains { $0.name == "graph_version" && $0.value == "321" })
        XCTAssertTrue(query.contains { $0.name == "edge_id" && $0.value == "9" })
    }

    @MainActor
    func testDLNAResolvesControlURLAndSendsSOAPWithoutAccountCredentials() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.httpMethod == "GET" {
                return Self.response(for: request, body: "<root><device><friendlyName>TV</friendlyName><serviceList><service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><controlURL>/transport</controlURL></service></serviceList></device></root>")
            }
            return Self.response(for: request, body: "<Envelope><Body><PlayResponse/></Body></Envelope>")
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=must-not-leak")
        let client = PiliDLNAClient(session: api.session)
        let device = try await client.device(at: URL(string: "http://192.168.1.9:8000/desc.xml")!)
        try await client.command("Play", service: device.transport, arguments: [("Speed", "1")])
        let request = try XCTUnwrap(recorder.requests.last)
        XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.9:8000/transport")
        XCTAssertEqual(request.value(forHTTPHeaderField: "SOAPACTION"), "\"urn:schemas-upnp-org:service:AVTransport:1#Play\"")
        let values = try UPnPSOAP.values(try XCTUnwrap(requestBodyData(from: request)))
        XCTAssertEqual(values["InstanceID"], "0")
        XCTAssertEqual(values["Speed"], "1")
        for request in recorder.requests {
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertFalse(request.httpShouldHandleCookies)
        }
    }

    @MainActor
    func testWebDAVUsesDepthZeroAndCreatesCollectionBeforeUploadingAndRestoring() async throws {
        let recorder = RequestContractRecorder()
        let archive = try SettingsArchive.capture(["piliplus.subtitle.bold": true])
        let data = try JSONEncoder().encode(archive)
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            let status: Int
            switch request.httpMethod {
            case "PROPFIND": status = 207
            case "MKCOL": status = 405 // An existing collection is not deleted or recreated.
            case "PUT": status = 204
            default: status = 200
            }
            return Self.response(for: request, statusCode: status, data: request.httpMethod == "GET" ? data : Data())
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=must-not-be-used")
        let client = try PiliWebDAVClient(address: "https://dav.example.com/user/", username: "alice", password: "example", session: api.session)
        try await client.testConnection()
        try await client.backup(archive)
        let restored = try await client.restore()
        XCTAssertEqual(restored.values.count, 1)
        XCTAssertEqual(recorder.requests.map(\.httpMethod), ["PROPFIND", "MKCOL", "PUT", "GET"])
        XCTAssertEqual(recorder.requests.first?.value(forHTTPHeaderField: "Depth"), "0")
        XCTAssertEqual(recorder.requests.first?.url?.absoluteString, "https://dav.example.com/user/")
        XCTAssertEqual(recorder.requests.last?.url?.path, "/user/PiliPlusSwift/settings.json")
        for request in recorder.requests {
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic " + Data("alice:example".utf8).base64EncodedString())
        }
    }

    @MainActor
    func testFavoriteFolderAndBatchMutationsPreserveAccountPrivacyAndResourceTypes() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, body: #"{"code":0,"data":{}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=favorite-session; DedeUserID=1001; bili_jct=favorite-csrf")
        let version = api.requestSnapshot(purpose: .interaction).playbackCredentialVersion
        try await api.savePiliFavoriteFolder(id: nil, title: "\u{6536}\u{85cf} A+B & C", intro: "\u{7b2c}\u{4e00}\u{884c}\n\u{7b2c}\u{4e8c}\u{884c}", isPublic: false, cover: "", credentialVersion: version)
        try await api.mutatePiliFavoriteItems(folderID: 8, aids: [12, 11, 12], action: .move(to: 9), credentialVersion: version)
        try await api.mutatePiliFavoriteItems(folderID: 8, aids: [11], action: .remove, credentialVersion: version)
        try await api.sortPiliFavoriteFolders(ids: [8, 10, 9], credentialVersion: version)
        XCTAssertEqual(recorder.requests.map { $0.url?.path }, ["/x/v3/fav/folder/add", "/x/v3/fav/resource/move", "/x/v3/fav/resource/batch-deal", "/x/v3/fav/folder/sort"])
        let create = formValues(in: recorder.requests[0])
        XCTAssertEqual(create["title"], "\u{6536}\u{85cf} A+B & C")
        XCTAssertEqual(create["intro"], "\u{7b2c}\u{4e00}\u{884c}\n\u{7b2c}\u{4e8c}\u{884c}")
        XCTAssertEqual(create["privacy"], "1")
        let encoded = String(decoding: try XCTUnwrap(requestBodyData(from: recorder.requests[0])), as: UTF8.self)
        XCTAssertTrue(encoded.contains("%2B"), "A literal plus must survive application/x-www-form-urlencoded decoding")
        let move = formValues(in: recorder.requests[1])
        XCTAssertEqual(move["resources"], "11:2,12:2")
        XCTAssertEqual(move["src_media_id"], "8")
        XCTAssertEqual(move["tar_media_id"], "9")
        XCTAssertEqual(move["mid"], "1001")
        XCTAssertEqual(formValues(in: recorder.requests[2])["del_media_ids"], "8")
        XCTAssertEqual(formValues(in: recorder.requests[3])["sort"], "8,10,9")
        XCTAssertNotNil(formValues(in: recorder.requests[3])["sign"])
        for request in recorder.requests {
            XCTAssertEqual(formValues(in: request)["csrf"], "favorite-csrf")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Cookie")?.contains("favorite-session") == true)
        }
        do {
            try await api.mutatePiliFavoriteItems(folderID: 8, aids: [11], action: .remove, credentialVersion: version - 1)
            XCTFail("Must reject stale account")
        } catch { XCTAssertEqual(recorder.requests.count, 4) }
    }

    @MainActor
    func testFavoriteMutationDoesNotRetryAnAmbiguousNetworkFailure() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in recorder.record(request); throw URLError(.networkConnectionLost) }
        let api = try makeAPI(cookieHeader: "SESSDATA=favorite-session; DedeUserID=1001; bili_jct=favorite-csrf")
        let version = api.requestSnapshot(purpose: .interaction).playbackCredentialVersion
        do {
            try await api.savePiliFavoriteFolder(id: nil, title: "\u{65b0}\u{6536}\u{85cf}\u{5939}", intro: "", isPublic: false, cover: "", credentialVersion: version)
            XCTFail("Expected network error")
        } catch { XCTAssertEqual(recorder.requests.count, 1) }
    }

    @MainActor
    func testWatchLaterPaginationKeepsAppliedFilterAndQueueUntilSearchIsSubmitted() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(for: request, body: #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#)
            }
            let page = Self.queryValues(for: request)["pn"] ?? "1"
            return Self.response(for: request, body: "{\"code\":0,\"data\":{\"count\":40,\"list\":[{\"bvid\":\"BVpage\(page)\",\"aid\":\(page),\"title\":\"\u{89c6}\u{9891}\(page)\"}]}}")
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=watch-session; DedeUserID=1001; bili_jct=watch-csrf")
        let model = MineViewModel(api: api, sessionStore: api.sessionStore)
        model.watchLaterFilter = PiliWatchLaterFilter(unfinished: true, ascending: true, keyword: "\u{65e7}\u{5173}\u{952e}\u{8bcd}")
        await model.refreshWatchLater()
        XCTAssertTrue(model.watchLaterHasMore)
        model.watchLaterFilter.keyword = "\u{5c1a}\u{672a}\u{63d0}\u{4ea4}"
        await model.loadMoreWatchLater()
        XCTAssertFalse(model.watchLaterHasMore)
        XCTAssertEqual(model.accountWatchLater.map(\.bvid), ["BVpage1", "BVpage2"])
        let requests = recorder.requests.filter { $0.url?.path == "/x/v2/history/toview/web" }
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { Self.queryValues(for: $0)["pn"] }, ["1", "2"])
        for request in requests {
            let query = Self.queryValues(for: request)
            XCTAssertEqual(query["key"], "\u{65e7}\u{5173}\u{952e}\u{8bcd}")
            XCTAssertEqual(query["viewed"], "2")
            XCTAssertEqual(query["asc"], "true")
            XCTAssertEqual(query["need_split"], "true")
            XCTAssertNotNil(query["w_rid"])
        }
        let queue = try XCTUnwrap(model.watchLaterPlaybackQueue)
        guard case let .watchLaterFiltered(filter) = queue.source else { return XCTFail("Missing filtered queue") }
        XCTAssertEqual(filter.keyword, "\u{65e7}\u{5173}\u{952e}\u{8bcd}")
        XCTAssertEqual(queue.bvids, ["BVpage1", "BVpage2"])
        await model.refreshWatchLater()
        XCTAssertEqual(Self.queryValues(for: try XCTUnwrap(recorder.requests.last))["key"], "\u{5c1a}\u{672a}\u{63d0}\u{4ea4}")
    }

    @MainActor
    func testWatchLaterCopyMoveAndRemovalUseTheHistoryAccountAndCorrectResourceTypes() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, body: #"{"code":0,"data":{"list":[{"id":7,"title":"\#u{76ee}\#u{6807}"}]}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=main-session; DedeUserID=1001; bili_jct=main-csrf", configure: { session, library in
            _ = try session.saveAdditionalAccount([
                Self.makeCookie(name: "DedeUserID", value: "2002"),
                Self.makeCookie(name: "SESSDATA", value: "history-session"),
                Self.makeCookie(name: "bili_jct", value: "history-csrf")
            ])
            try session.selectPlaybackAccount(mid: 2002)
            try session.setHistoryAccountPolicy(.playback)
            library.setMultiAccountExperimentEnabled(true)
        })
        let version = api.requestSnapshot(purpose: .historyRead).playbackCredentialVersion
        let folders = try await api.fetchPiliFavoriteDestinations(purpose: .historyRead)
        XCTAssertEqual(folders.first?.id, 7)
        try await api.mutatePiliWatchLater(aids: [12, 11, 12], targetFolder: 7, credentialVersion: version)
        try await api.mutatePiliWatchLater(aids: [11], targetFolder: 7, move: true, credentialVersion: version)
        try await api.mutatePiliWatchLater(aids: [11, 12], credentialVersion: version)
        XCTAssertEqual(recorder.requests.map { $0.url?.path }, ["/x/v3/fav/folder/created/list-all", "/x/v2/history/toview/copy", "/x/v2/history/toview/move", "/x/v2/history/toview/v2/dels"])
        XCTAssertEqual(Self.queryValues(for: recorder.requests[0])["up_mid"], "2002")
        XCTAssertEqual(formValues(in: recorder.requests[1])["resources"], "11,12")
        XCTAssertEqual(formValues(in: recorder.requests[1])["mid"], "2002")
        XCTAssertEqual(formValues(in: recorder.requests[2])["resources"], "11")
        XCTAssertEqual(formValues(in: recorder.requests[2])["tar_media_id"], "7")
        XCTAssertEqual(formValues(in: recorder.requests[3])["resources"], "11,12")
        for request in recorder.requests {
            XCTAssertEqual(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"], "history-session")
            if request.httpMethod == "POST" { XCTAssertEqual(formValues(in: request)["csrf"], "history-csrf") }
        }
        try api.sessionStore.setHistoryAccountPolicy(.main)
        do {
            try await api.mutatePiliWatchLater(aids: [11], credentialVersion: version)
            XCTFail("Reject stale history account")
        } catch { XCTAssertEqual(recorder.requests.count, 4) }
        do {
            try await api.cleanWatchLater(.all, credentialVersion: version)
            XCTFail("Cleanup must not affect the newly selected account")
        } catch { XCTAssertEqual(recorder.requests.count, 4) }
        RequestContractURLProtocol.install { request in recorder.record(request); throw URLError(.networkConnectionLost) }
        do {
            try await api.mutatePiliWatchLater(aids: [11], targetFolder: 7, credentialVersion: api.requestSnapshot(purpose: .historyRead).playbackCredentialVersion)
            XCTFail("Expected network failure")
        } catch { XCTAssertEqual(recorder.requests.count, 5, "Do not repeat an ambiguous write") }
    }

    @MainActor
    func testHistoryKeepsNonVideoRecordsExactDeletionKeysAndRawPaginationCursor() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, body: #"{"code":0,"data":{"tab":[{"type":"all","name":"\#u{5168}\#u{90e8}"},{"type":"archive","name":"\#u{89c6}\#u{9891}"},{"type":"live","name":"\#u{76f4}\#u{64ad}"}],"list":[{"kid":71,"title":"\#u{89c6}\#u{9891}","history":{"business":"archive","oid":101,"bvid":"BVhistoryA","cid":201},"view_at":1300,"progress":-1,"duration":90},{"kid":72,"title":"\#u{76f4}\#u{64ad}","history":{"business":"live","oid":102},"view_at":1200},{"kid":73,"title":"\#u{4e13}\#u{680f}","history":{"business":"article","oid":103},"view_at":1100},{"title":"\#u{672a}\#u{77e5}\#u{7c7b}\#u{578b}","history":{"business":"future-type","oid":104},"view_at":1000}]}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=history-session; DedeUserID=1001; bili_jct=history-csrf")
        let version = api.requestSnapshot(purpose: .historyRead).playbackCredentialVersion
        let first = try await api.fetchPiliHistoryPage(credentialVersion: version)
        XCTAssertEqual(first.records.count, 4)
        XCTAssertEqual(first.records.first?.video?.bvid, "BVhistoryA")
        XCTAssertEqual(first.records.first?.progress, -1)
        XCTAssertEqual(first.records.first?.deletionKey, "archive_71", "Deletion uses kid, not history.oid")
        XCTAssertEqual(first.records[1].destinationURL?.absoluteString, "https://live.bilibili.com/102")
        XCTAssertEqual(first.records[2].destinationURL?.absoluteString, "https://www.bilibili.com/read/cv103")
        XCTAssertNil(first.records[3].deletionKey, "Never guess a missing deletion key")
        XCTAssertEqual(first.tabs.map(\.id), ["all", "archive", "live"])
        XCTAssertEqual(first.cursorMax, 104)
        XCTAssertEqual(first.cursorViewedAt, 1000)
        XCTAssertTrue(first.hasMore)
        let second = try await api.fetchPiliHistoryPage(max: first.cursorMax, viewedAt: first.cursorViewedAt, credentialVersion: version)
        XCTAssertFalse(second.hasMore, "A repeated cursor must not loop forever")
        _ = try await api.fetchPiliHistoryPage(keyword: "\u{6d4b}\u{8bd5}", page: 2, credentialVersion: version)
        XCTAssertEqual(Self.queryValues(for: recorder.requests[0]), ["type": "all", "ps": "20", "max": "0", "view_at": "0"])
        XCTAssertEqual(Self.queryValues(for: recorder.requests[1])["max"], "104")
        XCTAssertEqual(recorder.requests[2].url?.path, "/x/web-interface/history/search")
        XCTAssertEqual(Self.queryValues(for: recorder.requests[2]), ["pn": "2", "keyword": "\u{6d4b}\u{8bd5}", "business": "all"])
    }

    @MainActor
    func testHistoryPauseSuppressesHeartbeatsAndDeletionStaysBoundToAccount() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/v2/history/shadow" {
                return Self.response(for: request, body: #"{"code":0,"data":false}"#)
            }
            return Self.response(for: request, body: #"{"code":0,"data":{}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=history-session; DedeUserID=1001; bili_jct=history-csrf")
        api.libraryStore.setMultiAccountExperimentEnabled(true)
        let version = api.requestSnapshot(purpose: .historyRead).playbackCredentialVersion
        let initial = try await api.fetchPiliHistoryPaused(credentialVersion: version)
        XCTAssertFalse(initial)
        try await api.mutatePiliHistory(.pause(true), credentialVersion: version)
        try await api.reportVideoHistory(aid: 101, cid: 201, progress: 35, duration: 90, bvid: "BVhistoryA")
        XCTAssertEqual(recorder.requests.count, 2, "Paused history must not send a heartbeat or fallback report")
        XCTAssertTrue(api.libraryStore.piliCloudHistoryPaused(mid: 1001))
        XCTAssertFalse(api.libraryStore.piliCloudHistoryPaused(mid: 2002), "Pause is scoped to its account")
        try await api.mutatePiliHistory(.pause(false), credentialVersion: version)
        try await api.reportVideoHistory(aid: 101, cid: 201, progress: 40, duration: 90, bvid: "BVhistoryA")
        XCTAssertEqual(recorder.requests.last?.url?.path, "/x/click-interface/web/heartbeat")
        try await api.mutatePiliHistory(.delete(keys: ["live_72", "archive_71", "archive_71"]), credentialVersion: version)
        XCTAssertEqual(formValues(in: try XCTUnwrap(recorder.requests.last))["kid"], "archive_71,live_72")
        try await api.mutatePiliHistory(.clear, credentialVersion: version)
        XCTAssertEqual(recorder.requests.last?.url?.path, "/x/v2/history/clear")
        for request in recorder.requests where request.httpMethod == "POST" {
            XCTAssertEqual(formValues(in: request)["csrf"], "history-csrf")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Cookie")?.contains("history-session") == true)
        }
        let count = recorder.requests.count
        try api.sessionStore.setHistoryAccountPolicy(.playback)
        do {
            try await api.mutatePiliHistory(.clear, credentialVersion: version)
            XCTFail("Reject stale history account version")
        } catch { XCTAssertEqual(recorder.requests.count, count) }
        RequestContractURLProtocol.install { request in recorder.record(request); throw URLError(.networkConnectionLost) }
        do {
            try await api.mutatePiliHistory(.clear, credentialVersion: api.requestSnapshot(purpose: .historyRead).playbackCredentialVersion)
            XCTFail("Expected transport failure")
        } catch { XCTAssertEqual(recorder.requests.count, count + 1, "Do not retry an ambiguous destructive write") }
    }

    @MainActor
    func testProfileFieldsUseSignedAppRequestsAndAvatarUsesMainAccountMultipart() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/v2/account/myinfo" {
                return Self.response(for: request, body: #"{"code":0,"data":{"mid":1001,"name":"\#u{539f}\#u{6635}\#u{79f0}","face":"https://i.example.com/avatar.jpg","sex":0,"sign":"\#u{539f}\#u{7b7e}\#u{540d}","birthday":"2000-01-01","coins":12}}"#)
            }
            return Self.response(for: request, body: #"{"code":0,"data":{}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=profile-session; DedeUserID=1001; bili_jct=profile-csrf", accessKey: "profile-access")
        let identity = PiliAccountIdentity(api.requestSnapshot(purpose: .main))
        let profile = try await api.fetchPiliOwnProfile(identity: identity)
        XCTAssertEqual(profile.name, "\u{539f}\u{6635}\u{79f0}")
        XCTAssertEqual(profile.coins, 12)
        try await api.updatePiliProfile(.uname, value: "\u{6635}\u{79f0}A+B", identity: identity)
        try await api.updatePiliProfile(.sign, value: "\u{65b0}\u{7b7e}\u{540d}", identity: identity)
        try await api.updatePiliProfile(.sex, value: "2", identity: identity)
        try await api.updatePiliProfile(.birthday, value: "2001-02-03", identity: identity)
        try await api.updatePiliAvatar(jpeg: Data("fixture-image".utf8), identity: identity)
        XCTAssertEqual(recorder.requests[0].url?.host, "app.bilibili.com")
        XCTAssertEqual(Self.queryValues(for: recorder.requests[0])["access_key"], "profile-access")
        XCTAssertEqual(recorder.requests.dropFirst().map { $0.url?.path }, ["/x/member/app/uname/update", "/x/member/app/sign/update", "/x/member/app/sex/update", "/x/member/app/birthday/update", "/x/member/web/face/update"])
        for request in recorder.requests[1...4] {
            let form = formValues(in: request)
            XCTAssertEqual(form["access_key"], "profile-access")
            XCTAssertEqual(form["mobi_app"], "android_hd")
            XCTAssertNotNil(form["sign"])
            XCTAssertEqual(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"], "profile-session")
        }
        XCTAssertEqual(formValues(in: recorder.requests[1])["uname"], "\u{6635}\u{79f0}A+B")
        XCTAssertEqual(formValues(in: recorder.requests[2])["user_sign"], "\u{65b0}\u{7b7e}\u{540d}")
        XCTAssertEqual(formValues(in: recorder.requests[3])["sex"], "2")
        XCTAssertEqual(formValues(in: recorder.requests[4])["birthday"], "2001-02-03")
        let avatar = recorder.requests[5]
        XCTAssertEqual(Self.queryValues(for: avatar)["csrf"], "profile-csrf")
        XCTAssertTrue(avatar.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(decoding: try XCTUnwrap(requestBodyData(from: avatar)), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"face\"; filename=\"avatar.jpg\""))
        XCTAssertTrue(body.contains("name=\"dopost\"\r\n\r\nsave"))
        XCTAssertTrue(body.contains("name=\"DisplayRank\"\r\n\r\n10000"))
    }

    @MainActor
    func testProfileRejectsMissingAppLoginAndStaleIdentityAndDoesNotRetryAvatarUpload() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in recorder.record(request); throw URLError(.networkConnectionLost) }
        let api = try makeAPI(cookieHeader: "SESSDATA=profile-session; DedeUserID=1001; bili_jct=profile-csrf")
        let identity = PiliAccountIdentity(api.requestSnapshot(purpose: .main))
        do {
            try await api.updatePiliProfile(.sign, value: "\u{7b7e}\u{540d}", identity: identity)
            XCTFail("Do not send an unsigned app profile mutation")
        } catch { XCTAssertTrue(recorder.requests.isEmpty) }
        do {
            try await api.updatePiliAvatar(jpeg: Data([1]), identity: identity)
            XCTFail("Expected upload error")
        } catch { XCTAssertEqual(recorder.requests.count, 1) }
        try api.sessionStore.logout()
        do {
            try await api.updatePiliAvatar(jpeg: Data([1]), identity: identity)
            XCTFail("Reject stale account")
        } catch { XCTAssertEqual(recorder.requests.count, 1) }
    }

    @MainActor
    func testRelationsKeepSubmittedGroupAndOrderDuringPaginationAndSearchAllFollowing() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch request.url?.path {
            case "/x/web-interface/nav":
                return Self.response(for: request, body: #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#)
            case "/x/relation/tag":
                let page = Self.queryValues(for: request)["pn"]
                let users = (page == "1" ? Array(1...20) : [21]).map { ["mid": $0, "uname": "\u{7528}\u{6237}\($0)"] as [String: Any] }
                let data = try JSONSerialization.data(withJSONObject: ["code": 0, "data": users])
                return Self.response(for: request, data: data)
            case "/x/relation/tags":
                return Self.response(for: request, body: #"{"code":0,"data":[{"tagid":0,"name":"\#u{9ed8}\#u{8ba4}\#u{5206}\#u{7ec4}","count":3},{"tagid":-10,"name":"\#u{7279}\#u{522b}\#u{5173}\#u{6ce8}","count":1},{"tagid":7,"name":"\#u{81ea}\#u{5b9a}\#u{4e49}","count":21}]}"#)
            default:
                return Self.response(for: request, body: #"{"code":0,"data":{"list":[{"mid":50,"uname":"\#u{641c}\#u{7d22}\#u{7528}\#u{6237}","attribute":6}],"total":1}}"#)
            }
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=relation-session; DedeUserID=1001; bili_jct=relation-csrf")
        let model = PiliRelationsModel(api: api)
        model.groupID = 7
        await model.start()
        XCTAssertEqual(model.groups.filter(\.isCustom).map(\.id), [7])
        XCTAssertEqual(model.users.count, 20)
        model.keyword = "\u{5c1a}\u{672a}\u{63d0}\u{4ea4}"; model.groupID = 8; model.frequent = true
        await model.load()
        XCTAssertEqual(model.users.count, 21)
        XCTAssertFalse(model.hasMore)
        let pages = recorder.requests.filter { $0.url?.path == "/x/relation/tag" }
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(Self.queryValues(for: pages[1])["tagid"], "7")
        XCTAssertEqual(Self.queryValues(for: pages[1])["order_type"], "")
        XCTAssertEqual(Self.queryValues(for: pages[1])["pn"], "2")
        model.keyword = "\u{732b}A+B"
        await model.load(reset: true)
        XCTAssertEqual(model.users.map(\.id), [50])
        let search = try XCTUnwrap(recorder.requests.last)
        XCTAssertEqual(search.url?.path, "/x/relation/followings/search")
        XCTAssertEqual(Self.queryValues(for: search)["name"], "\u{732b}A+B")
        XCTAssertNotNil(Self.queryValues(for: search)["w_rid"])
        XCTAssertNil(Self.queryValues(for: search)["tagid"], "Search spans all following, not just the previous group")
        XCTAssertEqual(cookieValues(in: search.value(forHTTPHeaderField: "Cookie"))["SESSDATA"], "relation-session")
    }

    @MainActor
    func testRelationMutationsKeepDefaultGroupAndFanRemovalContracts() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/relation" {
                return Self.response(for: request, body: #"{"code":0,"data":{"attribute":6,"tag":[0,7],"special":1}}"#)
            }
            return Self.response(for: request, body: #"{"code":0,"data":{"tagid":8}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=relation-session; DedeUserID=1001; bili_jct=relation-csrf")
        let identity = PiliAccountIdentity(api.requestSnapshot(purpose: .main))
        let groups = try await api.fetchPiliRelationGroups(mid: 20, identity: identity)
        XCTAssertEqual(groups, Set([-10, 7]))
        let created = try await api.mutatePiliRelation(.createGroup("A+B"), identity: identity)
        XCTAssertEqual(created, 8)
        try await api.mutatePiliRelation(.renameGroup(8, "\u{65b0}\u{5206}\u{7ec4}"), identity: identity)
        try await api.mutatePiliRelation(.sortGroups([8, 7]), identity: identity)
        try await api.mutatePiliRelation(.setGroups(mid: 20, ids: Array(groups)), identity: identity)
        try await api.mutatePiliRelation(.setGroups(mid: 20, ids: []), identity: identity)
        try await api.mutatePiliRelation(.removeFan(20), identity: identity)
        try await api.mutatePiliRelation(.unblock(30), identity: identity)
        let writes = recorder.requests.filter { $0.httpMethod == "POST" }
        XCTAssertEqual(writes.count, 7)
        XCTAssertEqual(formValues(in: writes[0])["tag"], "A+B")
        XCTAssertEqual(formValues(in: writes[1])["name"], "\u{65b0}\u{5206}\u{7ec4}")
        XCTAssertEqual(formValues(in: writes[2])["tagids"], "8,7", "Preserve user-defined order")
        XCTAssertEqual(formValues(in: writes[3])["tagids"], "-10,7")
        XCTAssertEqual(formValues(in: writes[4])["tagids"], "0", "An empty selection must explicitly choose the default group")
        XCTAssertEqual(writes[5].url?.path, "/x/relation/modify")
        XCTAssertEqual(formValues(in: writes[5])["act"], "7", "Removing a fan must not issue unfollow or blacklist")
        XCTAssertEqual(formValues(in: writes[6])["act"], "6")
        for request in writes {
            XCTAssertEqual(formValues(in: request)["csrf"], "relation-csrf")
            XCTAssertEqual(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"], "relation-session")
            XCTAssertNotNil(Self.queryValues(for: request)["x-bili-device-req-json"])
        }
        XCTAssertEqual(writes[5].value(forHTTPHeaderField: "Origin"), "https://space.bilibili.com")
        XCTAssertEqual(writes[5].value(forHTTPHeaderField: "Referer"), "https://space.bilibili.com/20/dynamic")
    }

    @MainActor
    func testRelationWritesRejectSystemGroupsStaleAccountsAndAmbiguousRetry() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in recorder.record(request); throw URLError(.networkConnectionLost) }
        let api = try makeAPI(cookieHeader: "SESSDATA=relation-session; DedeUserID=1001; bili_jct=relation-csrf")
        let identity = PiliAccountIdentity(api.requestSnapshot(purpose: .main))
        for action in [PiliRelationMutation.deleteGroup(0), .renameGroup(-10, "\u{6539}\u{540d}"), .sortGroups([7, -2]), .block(1001)] {
            do { try await api.mutatePiliRelation(action, identity: identity); XCTFail("Reject a protected target") }
            catch { XCTAssertTrue(recorder.requests.isEmpty) }
        }
        do { try await api.mutatePiliRelation(.removeFan(20), identity: identity); XCTFail("Expected transport failure") }
        catch { XCTAssertEqual(recorder.requests.count, 1, "Do not retry a potentially completed relation mutation") }
        try api.sessionStore.logout()
        do { try await api.mutatePiliRelation(.createGroup("\u{5206}\u{7ec4}"), identity: identity); XCTFail("Reject stale account") }
        catch { XCTAssertEqual(recorder.requests.count, 1) }
    }

    @MainActor
    func testNoteSaveUsesOneAccountAndEncodesTextWithoutPublishingComments() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, body: #"{"code":0,"data":{"note_id":123456789}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=note-session; DedeUserID=1001; bili_jct=note-csrf")
        let version = api.requestSnapshot(purpose: .main).playbackCredentialVersion
        let result = try await api.savePiliNote(aid: 123, noteID: nil, title: "\u{6807}\u{9898}", text: "\u{7b2c}\u{4e00}\u{884c}\nA&B", published: false, credentialVersion: version)
        XCTAssertEqual(result, "123456789")
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/note/add")
        let body = formValues(in: request)
        XCTAssertEqual(body["csrf"], "note-csrf")
        XCTAssertEqual(body["publish"], "0")
        XCTAssertEqual(body["auto_comment"], "0")
        let operations = try JSONDecoder().decode([[String: String]].self, from: Data(try XCTUnwrap(body["content"]).utf8))
        XCTAssertEqual(operations.first?["insert"], "\u{7b2c}\u{4e00}\u{884c}\nA&B\n")
        do {
            _ = try await api.savePiliNote(aid: 123, noteID: nil, title: "\u{6807}\u{9898}", text: "\u{5185}\u{5bb9}", published: true, credentialVersion: version - 1)
            XCTFail("Stale account must be rejected")
        } catch { XCTAssertEqual(recorder.requests.count, 1) }
    }

    @MainActor
    func testCommentMutationsBindInteractionAccountAndRetainDynamicType() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, body: #"{"code":0}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=main-session; DedeUserID=1001; bili_jct=main-csrf", configure: { session, library in
            library.setMultiAccountExperimentEnabled(true)
            _ = try session.saveAdditionalAccount([Self.makeCookie(name: "SESSDATA", value: "interaction-session"), Self.makeCookie(name: "DedeUserID", value: "2002"), Self.makeCookie(name: "bili_jct", value: "interaction-csrf")])
            try session.selectInteractionAccount(mid: 2002)
        })
        let identity = PiliAccountIdentity(api.requestSnapshot(purpose: .interaction))
        let actions: [PiliCommentMutation] = [.like(true), .dislike(true), .dislike(false), .pin(true), .pin(false), .delete, .report(reason: 0, text: "\u{8bf4}\u{660e} A+B & \u{5185}\u{5bb9}")]
        for action in actions {
            try await api.mutatePiliComment(action, oid: "987654321012345678", type: 17, rpid: 88, identity: identity, referer: "https://t.bilibili.com/123")
        }
        XCTAssertEqual(recorder.requests.map { $0.url?.lastPathComponent }, ["action", "hate", "hate", "top", "top", "del", "report"])
        for request in recorder.requests {
            let body = formValues(in: request)
            XCTAssertEqual(body["type"], "17", "Dynamic reports must not be sent as video reports")
            XCTAssertEqual(body["oid"], "987654321012345678")
            XCTAssertEqual(body["rpid"], "88")
            XCTAssertEqual(body["csrf"], "interaction-csrf")
            XCTAssertEqual(cookieValues(in: request.value(forHTTPHeaderField: "Cookie"))["SESSDATA"], "interaction-session")
        }
        XCTAssertEqual(formValues(in: recorder.requests[2])["action"], "0")
        XCTAssertEqual(formValues(in: recorder.requests[6])["content"], "\u{8bf4}\u{660e} A+B & \u{5185}\u{5bb9}")
        XCTAssertEqual(formValues(in: recorder.requests[6])["add_blacklist"], "false")
    }

    @MainActor
    func testCommentMutationsRejectStaleIdentityAndDoNotRetryAmbiguousWrite() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in recorder.record(request); throw URLError(.networkConnectionLost) }
        let api = try makeAPI(cookieHeader: "SESSDATA=comment-session; DedeUserID=1001; bili_jct=comment-csrf")
        let identity = PiliAccountIdentity(api.requestSnapshot(purpose: .interaction))
        for action in [PiliCommentMutation.report(reason: 0, text: " "), .report(reason: 22, text: ""), .report(reason: 999, text: "test")] {
            do { try await api.mutatePiliComment(action, oid: "123", type: 1, rpid: 7, identity: identity, referer: "https://www.bilibili.com"); XCTFail("Reject invalid report") }
            catch { XCTAssertTrue(recorder.requests.isEmpty) }
        }
        do { try await api.mutatePiliComment(.delete, oid: "123", type: 1, rpid: 7, identity: identity, referer: "https://www.bilibili.com"); XCTFail("Expected error") }
        catch { XCTAssertEqual(recorder.requests.count, 1) }
        try api.sessionStore.logout()
        do { try await api.mutatePiliComment(.pin(true), oid: "123", type: 1, rpid: 7, identity: identity, referer: "https://www.bilibili.com"); XCTFail("Reject stale identity") }
        catch { XCTAssertEqual(recorder.requests.count, 1) }
    }

    @MainActor
    func testFailedCommentReactionLeavesSharedStateUnchanged() async throws {
        RequestContractURLProtocol.install { request in Self.response(for: request, body: #"{"code":-403,"message":"\#u{6ca1}\#u{6709}\#u{6743}\#u{9650}"}"#) }
        let api = try makeAPI(cookieHeader: "SESSDATA=comment-session; DedeUserID=1001; bili_jct=comment-csrf")
        let subject = PiliCommentActionStore.Subject(identity: PiliAccountIdentity(api.requestSnapshot(purpose: .interaction)), oid: "123", type: 1)
        let comment = try JSONDecoder().decode(Comment.self, from: Data(#"{"rpid":7,"like":9,"action":1}"#.utf8))
        let store = PiliCommentActionStore()
        do { try await store.perform(.dislike(true), comment: comment, subject: subject, referer: "https://www.bilibili.com", api: api); XCTFail("Expected permission error") }
        catch { XCTAssertEqual(store.state(comment, subject: subject), PiliCommentState(comment: comment)) }
        XCTAssertFalse(store.isBusy(subject))
    }

    @MainActor
    func testChatSettingsRespectServerVisibilityAndPushFlagPolarity() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.lastPathComponent == "get_session_ss" {
                return Self.response(for: request, body: #"{"code":0,"data":{"show_push_setting":1,"push_setting":0}}"#)
            }
            if request.url?.lastPathComponent == "get_msg_dnd" {
                return Self.response(for: request, body: #"{"code":0,"data":{"uid_settings":[{"setting":1}]}}"#)
            }
            return Self.response(for: request, body: #"{"code":0}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=chat-session; DedeUserID=1001; bili_jct=chat-csrf")
        let identity = PiliAccountIdentity(api.requestSnapshot())
        let settings = try await api.fetchPiliChatSettings(talkerID: 20, identity: identity)
        XCTAssertTrue(settings.receivesPush)
        XCTAssertTrue(settings.canConfigurePush)
        XCTAssertTrue(settings.muted, "The upstream response can omit uid for a single requested user")
        try await api.setPiliChatSetting(talkerID: 20, receivesPush: false, identity: identity)
        try await api.setPiliChatSetting(talkerID: 20, muted: false, identity: identity)
        let writes = recorder.requests.filter { $0.httpMethod == "POST" }
        XCTAssertEqual(writes.map { $0.url?.lastPathComponent }, ["set_push_ss", "set_msg_dnd"])
        XCTAssertEqual(formValues(in: writes[0])["setting"], "1")
        XCTAssertEqual(formValues(in: writes[0])["talker_uid"], "20")
        XCTAssertEqual(formValues(in: writes[1])["setting"], "0")
        XCTAssertEqual(formValues(in: writes[1])["dnd_uid"], "20")
        for request in writes { XCTAssertEqual(formValues(in: request)["csrf"], "chat-csrf") }
        try api.sessionStore.logout()
        do { try await api.setPiliChatSetting(talkerID: 20, receivesPush: true, identity: identity); XCTFail("Reject stale account") }
        catch { XCTAssertEqual(recorder.requests.count, 4) }
    }

    @MainActor
    func testBatchAudioDownloadReadsAllFavoritePagesAndDeduplicatesWithoutMediaTransfers() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            let path = request.url?.path ?? ""
            let query = Self.queryValues(for: request)
            if path == "/x/v3/fav/resource/list" {
                let body = query["pn"] == "1"
                    ? #"{"code":0,"data":{"has_more":true,"medias":[{"bvid":"BVbatchone","aid":1,"title":"one"}]}}"#
                    : #"{"code":0,"data":{"has_more":false,"medias":[{"bvid":"BVbatchone","aid":1,"title":"one"},{"bvid":"BVbatchtwo","aid":2,"title":"two"}]}}"#
                return Self.response(for: request, body: body)
            }
            if path == "/x/web-interface/view" {
                let bvid = query["bvid"] ?? ""
                let cid = bvid == "BVbatchone" ? 11 : 22
                return Self.response(for: request, body: "{\"code\":0,\"data\":{\"bvid\":\"\(bvid)\",\"title\":\"batch\",\"cid\":\(cid),\"pages\":[{\"cid\":\(cid),\"page\":1}]}}")
            }
            if path == "/x/web-interface/nav" {
                return Self.response(for: request, body: #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#)
            }
            if path.contains("playurl") {
                return Self.response(for: request, body: #"{"code":0,"data":{"quality":64,"accept_quality":[64],"dash":{"duration":10,"video":[{"id":64,"baseUrl":"https://example.com/video.m4s","codecs":"avc1.640028","codecid":7,"mimeType":"video/mp4"}],"audio":[{"id":30280,"baseUrl":"https://example.com/audio.m4s","codecs":"mp4a.40.2","mimeType":"audio/mp4","bandwidth":192000}]}}}"#)
            }
            throw URLError(.badServerResponse)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=batch-session; DedeUserID=1001")
        let request = PiliBatchDownloadRequest(source: .favorite(id: 7, keyword: "A+B", order: .favoriteTime),
            title: "\u{6536}\u{85cf}\u{5939}", purpose: .interaction, credentialVersion: api.requestSnapshot(purpose: .interaction).playbackCredentialVersion)
        let sink = BatchDownloadTestSink()
        let model = PiliBatchDownloadModel(api: api, request: request, downloads: sink)
        model.mediaKind = .audio
        model.start()
        await model.waitUntilFinished()
        XCTAssertEqual(model.addedCount, 2, model.status + model.failures.joined())
        XCTAssertTrue(model.failures.isEmpty, model.failures.joined())
        XCTAssertEqual(sink.audioCIDs, [11, 22])
        XCTAssertEqual(sink.videoCount, 0)
        let pages = recorder.requests.filter { $0.url?.path == "/x/v3/fav/resource/list" }
        XCTAssertEqual(pages.map { Self.queryValues(for: $0)["pn"] }, ["1", "2"])
        XCTAssertTrue(pages.allSatisfy { Self.queryValues(for: $0)["keyword"] == "A+B" })
        XCTAssertFalse(recorder.requests.contains { $0.url?.host == "example.com" })
    }

    @MainActor
    func testBatchDownloadRejectsStaleAccountAndImmediateCancellationBeforeEnqueue() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            throw URLError(.badServerResponse)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=batch-session; DedeUserID=1001")
        let version = api.requestSnapshot(purpose: .interaction).playbackCredentialVersion
        let sink = BatchDownloadTestSink()
        let stale = PiliBatchDownloadRequest(source: .favorite(id: 7, keyword: "", order: .favoriteTime),
                                             title: "\u{6536}\u{85cf}", purpose: .interaction, credentialVersion: version + 1)
        let model = PiliBatchDownloadModel(api: api, request: stale, downloads: sink)
        model.start()
        await model.waitUntilFinished()
        XCTAssertTrue(model.status.contains("\u{8d26}\u{53f7}\u{5df2}\u{5207}\u{6362}"))
        XCTAssertTrue(recorder.requests.isEmpty)
        let current = PiliBatchDownloadRequest(source: .favorite(id: 7, keyword: "", order: .favoriteTime),
                                               title: "\u{6536}\u{85cf}", purpose: .interaction, credentialVersion: version)
        let cancelled = PiliBatchDownloadModel(api: api, request: current, downloads: sink)
        cancelled.start(); cancelled.cancel()
        await cancelled.waitUntilFinished()
        XCTAssertTrue(cancelled.status.contains("\u{5df2}\u{505c}\u{6b62}"))
        XCTAssertTrue(recorder.requests.isEmpty)
        XCTAssertTrue(sink.audioCIDs.isEmpty)
    }

    @MainActor
    func testIndependentAndAnonymousCommentReadersKeepWritesOnInteractionAccount() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, body: #"{"code":0,"data":{"replies":[{"rpid":9,"action":1,"like":10}]}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=main; DedeUserID=1001; bili_jct=main-csrf", configure: { store, library in
            library.setMultiAccountExperimentEnabled(true)
            try store.saveLoginCookies(["SESSDATA": "reader", "DedeUserID": "2002", "bili_jct": "reader-csrf"], credentialKind: .web)
            try store.selectMainAccount(mid: 1001)
            try store.selectInteractionAccount(mid: 1001)
            try store.setCommentReadPolicy(.account, mid: 2002)
        })
        let page = try await api.fetchComments(aid: 7)
        XCTAssertNil(page.replies?.first?.likeState)
        XCTAssertEqual(page.replies?.first?.like, 10)
        XCTAssertTrue(recorder.request?.value(forHTTPHeaderField: "Cookie")?.contains("SESSDATA=reader") == true)
        try api.sessionStore.setCommentReadPolicy(.anonymous)
        _ = try await api.fetchComments(aid: 7)
        _ = try await api.fetchCommentReplies(aid: 7, root: 9)
        _ = try await api.fetchCommentDialog(aid: 7, root: 9, dialog: 10)
        for request in recorder.requests.dropFirst() {
            let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
            XCTAssertFalse(cookie.contains("SESSDATA"))
            XCTAssertFalse(cookie.contains("bili_jct"))
            XCTAssertFalse(cookie.contains("DedeUserID"))
        }
        let identity = PiliAccountIdentity(api.requestSnapshot(purpose: .interaction))
        try await api.mutatePiliComment(.like(true), oid: "7", type: 1, rpid: 9, identity: identity, referer: "https://www.bilibili.com/video/BVtest")
        XCTAssertTrue(recorder.request?.value(forHTTPHeaderField: "Cookie")?.contains("SESSDATA=main") == true)
        XCTAssertEqual(recorder.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }

    @MainActor
    func testLiveProbeFollowsHLSMediaCapsSampleBytesAndDoesNotForwardCredentials() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            let isPlaylist = request.url?.pathExtension == "m3u8"
            let data = isPlaylist ? Data("#EXTM3U\n#EXTINF:4,\nsegment1.ts\n#EXTINF:4,\nsegment2.ts\n".utf8) : Data(repeating: 0x47, count: 400_000)
            return Self.response(for: request, headerFields: ["Content-Type": isPlaylist ? "application/vnd.apple.mpegurl" : "video/mp2t"], data: data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestContractURLProtocol.self]
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = LiveCDNProbeService(session: session)
        let result = try await service.probe(url: URL(string: "https://cdn.example.com/live/index.m3u8")!,
            headers: ["User-Agent": "probe", "Referer": "https://live.bilibili.com/", "Cookie": "secret", "Authorization": "secret"]) { _ in }
        XCTAssertGreaterThan(result.bytes, 0)
        XCTAssertLessThanOrEqual(result.bytes, LiveCDNProbeService.byteLimit)
        XCTAssertEqual(result.phase, "\u{5b8c}\u{6210}")
        XCTAssertEqual(recorder.requests.map { $0.url?.lastPathComponent }, ["index.m3u8", "segment1.ts"])
        XCTAssertTrue(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == nil && $0.value(forHTTPHeaderField: "Authorization") == nil })
        XCTAssertTrue(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "Range") != nil })
        let model = LiveCDNProbeModel(service: service)
        model.start(candidates: [.init(url: URL(string: "https://cdn.example.com/live.ts")!, protocolName: nil, formatName: nil, codecName: nil, currentQN: nil, qualityTitle: nil, source: "test")], headers: [:])
        model.cancel()
        await model.waitUntilFinished()
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.completed, 0)
        XCTAssertTrue(model.message?.contains("\u{5df2}\u{53d6}\u{6d88}") == true)
    }

    @MainActor
    func testCommentResponseIsDiscardedWhenReaderChangesInFlight() async throws {
        let api = try makeAPI(cookieHeader: "SESSDATA=main; DedeUserID=1001", configure: { _, library in
            library.setMultiAccountExperimentEnabled(true)
        })
        RequestContractURLProtocol.install { request in
            let changed = DispatchSemaphore(value: 0)
            Task { @MainActor in
                try? api.sessionStore.setCommentReadPolicy(.anonymous)
                changed.signal()
            }
            guard changed.wait(timeout: .now() + 3) == .success else { throw URLError(.timedOut) }
            return Self.response(for: request, body: #"{"code":0,"data":{"replies":[]}}"#)
        }
        do {
            _ = try await api.fetchComments(aid: 7)
            XCTFail("Old reader response must not reach the comment list")
        } catch { XCTAssertTrue(error is CancellationError, "\(error)") }
    }

    @MainActor
    func testPublishedVisibilityUsesAnonymousReadAndDoesNotRepublish() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/polymer/web-dynamic/v1/detail" {
                return Self.response(for: request, body: #"{"code":0,"data":{"item":{"id_str":"901"}}}"#)
            }
            return Self.response(for: request, body: #"{"code":0,"data":{"root":{"rpid":70},"replies":[{"rpid":71}]}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=private; DedeUserID=1001; bili_jct=private-csrf")
        let dynamic = try await api.piliCheckVisibility(.dynamic("901"), identity: .init(api.requestSnapshot()))
        let reply = try await api.piliCheckVisibility(.comment(oid: "100", type: 1, id: 71, root: 70), identity: .init(api.requestSnapshot(purpose: .interaction)))
        XCTAssertTrue(dynamic.publicRead)
        XCTAssertTrue(reply.publicRead)
        XCTAssertEqual(recorder.requests.count, 2)
        for request in recorder.requests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue((request.value(forHTTPHeaderField: "Cookie") ?? "").isEmpty)
        }
        RequestContractURLProtocol.install { request in
            Self.response(for: request, body: #"{"code":-404,"message":"not found"}"#)
        }
        let unknown = try await api.piliCheckVisibility(.dynamic("901"), identity: .init(api.requestSnapshot()))
        XCTAssertFalse(unknown.publicRead)
        XCTAssertTrue(unknown.message.contains("\u{5ba1}\u{6838}\u{5ef6}\u{8fdf}"), "An anonymous read failure is not proof of moderation")
    }

    @MainActor
    func testIncognitoPlaybackDropsCredentialsAndInvalidatesScopeWithoutAffectingInteractions() async throws {
        let api = try makeAPI(cookieHeader: "SESSDATA=private; DedeUserID=1001; bili_jct=private-csrf", accessKey: "private-access")
        let before = api.requestSnapshot(purpose: .playback)
        api.libraryStore.setIncognitoModeEnabled(true)
        let anonymous = api.requestSnapshot(purpose: .playback)
        XCTAssertFalse(anonymous.isLoggedIn)
        XCTAssertNil(anonymous.appAccessKey)
        XCTAssertNil(anonymous.csrfToken)
        XCTAssertNil(anonymous.currentUserMID)
        XCTAssertFalse(anonymous.cookieHeader.contains("SESSDATA"))
        XCTAssertNotEqual(before.playbackCredentialVersion, anonymous.playbackCredentialVersion)
        XCTAssertTrue(api.requestSnapshot(purpose: .interaction).isLoggedIn)
        XCTAssertTrue(api.requestSnapshot().cookieHeader.contains("private"))
        let history = await api.playbackHistoryRequestContext()
        XCTAssertFalse(history.isAccountPurposeEnabled)
        api.libraryStore.setIncognitoModeEnabled(false)
        let restored = api.requestSnapshot(purpose: .playback)
        XCTAssertTrue(restored.isLoggedIn)
        XCTAssertNotEqual(restored.playbackCredentialVersion, before.playbackCredentialVersion, "Off/on/off must not accept a stale request")
    }

    @MainActor
    func testLiveEmotesAndSendingUseRoomScopedSignedOneAttemptRequests() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(for: request, body: #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#)
            }
            if request.url?.path == "/xlive/web-ucenter/v2/emoticon/GetEmoticons" {
                return Self.response(for: request, body: #"{"code":0,"data":{"data":[{"pkg_type":3,"emoticons":[{"emoji":"[dog]","emoticon_unique":"official_dog","perm":1}]},{"pkg_type":2,"emoticons":[{"emoji":"\#u{52a0}\#u{6cb9}","emoticon_unique":"room_1_2","perm":0}]}]}}"#)
            }
            return Self.response(for: request, body: #"{"code":0,"data":{}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=live; DedeUserID=1001; bili_jct=live-csrf")
        let identity = PiliAccountIdentity(api.requestSnapshot())
        let emotes = try await api.piliLiveEmotes(roomID: 99, identity: identity)
        XCTAssertEqual(emotes.count, 2)
        XCTAssertTrue(emotes[0].insertsText)
        XCTAssertFalse(emotes[1].allowed)
        try await api.piliSendLive(roomID: 99, message: "[dog] hello", emote: false, identity: identity)
        try await api.piliSendLive(roomID: 99, message: "room_99_3", emote: true, identity: identity)
        let writes = recorder.requests.filter { $0.httpMethod == "POST" }
        XCTAssertEqual(writes.count, 2)
        for request in writes {
            XCTAssertEqual(request.url?.host, "api.live.bilibili.com")
            XCTAssertEqual(request.url?.path, "/msg/send")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://live.bilibili.com/99")
            XCTAssertNotNil(Self.queryValues(for: request)["w_rid"])
            XCTAssertEqual(formValues(in: request)["csrf_token"], "live-csrf")
            XCTAssertEqual(formValues(in: request)["roomid"], "99")
        }
        XCTAssertNil(formValues(in: writes[0])["dm_type"])
        XCTAssertEqual(formValues(in: writes[1])["dm_type"], "1")
        let failures = RequestContractRecorder()
        RequestContractURLProtocol.install { request in failures.record(request); throw URLError(.networkConnectionLost) }
        do { try await api.piliSendLive(roomID: 99, message: "message", emote: false, identity: identity); XCTFail() }
        catch { XCTAssertEqual(failures.requests.filter { $0.httpMethod == "POST" }.count, 1) }
    }

    @MainActor
    func testDynamicReservationUsesNumericStatusAndServerUpdatedState() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, body: #"{"code":0,"data":{"final_btn_status":2,"reserve_update":18,"desc_update":"18 \#u{4eba}\#u{9884}\#u{7ea6}"}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=reservation; DedeUserID=1001; bili_jct=reservation-csrf")
        let result = try await api.piliToggleDynamicReservation(id: 55, dynamicID: "66", status: 1, total: 17, identity: .init(api.requestSnapshot()))
        XCTAssertEqual(result["final_btn_status"].piliInt, 2)
        let request = try XCTUnwrap(recorder.request)
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(requestBodyData(from: request))) as? [String: Any]
        XCTAssertEqual(request.url?.path, "/x/dynamic/feed/reserve/click")
        XCTAssertEqual(body?["reserve_id"] as? Int, 55)
        XCTAssertEqual(body?["cur_btn_status"] as? Int, 1)
        XCTAssertEqual(body?["dynamic_id_str"] as? String, "66")
    }

    @MainActor
    func testCastingQueueLazilyPagesAndRejectsChangedListAccount() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, body: #"{"code":0,"data":{"has_more":false,"medias":[{"bvid":"BVfirst","aid":1},{"bvid":"BVnext","aid":2,"title":"Next"}]}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=queue; DedeUserID=1001; bili_jct=queue-csrf")
        let initial = PiliPlaybackQueue(source: .favoriteFolder(80), credentialVersion: api.sessionStore.interactionAccountCredentialVersion,
            bvids: ["BVfirst"], nextPage: 2)
        let expanded = try await PiliCastSource.expandedCastQueue(initial, api: api)
        XCTAssertEqual(expanded.bvids, ["BVfirst", "BVnext"])
        XCTAssertEqual(expanded.titles["BVnext"], "Next")
        XCTAssertNil(expanded.nextPage)
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(Self.queryValues(for: try XCTUnwrap(recorder.request))["pn"], "2")
        let stale = PiliPlaybackQueue(source: .favoriteFolder(80), credentialVersion: -1, bvids: ["BVfirst"], nextPage: 2)
        do { _ = try await PiliCastSource.expandedCastQueue(stale, api: api); XCTFail("Reject stale credentials before fetching") }
        catch { XCTAssertEqual(recorder.requests.count, 1) }
    }

    @MainActor
    func testSearchDurationLiveRoomsAndDefaultWordUseDistinctContracts() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(for: request, body: #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#)
            }
            if request.url?.path == "/x/web-interface/search/default" {
                return Self.response(for: request, body: #"{"code":0,"data":{"name":"actual query","show_name":"display title"}}"#)
            }
            if Self.queryValues(for: request)["search_type"] == "live_room" {
                return Self.response(for: request, body: #"{"code":0,"data":{"result":[{"roomid":99,"title":"<em>\#u{76f4}\#u{64ad}</em>\#u{95f4}","uname":"\#u{4e3b}\#u{64ad}","uid":42,"user_cover":"//i.example.com/cover.jpg"}]}}"#)
            }
            return Self.response(for: request, body: #"{"code":0,"data":{"result":[]}}"#)
        }
        let api = try makeAPI(cookieHeader: "")
        _ = try await api.searchVideos(keyword: "duration", order: "click", duration: 3)
        let rooms = try await api.piliSearchLiveRooms(keyword: "live", page: 2)
        let word = try await api.piliDefaultSearch()
        XCTAssertEqual(rooms.first?.roomID, 99); XCTAssertEqual(rooms.first?.title, "\u{76f4}\u{64ad}\u{95f4}")
        XCTAssertEqual(word?.keyword, "actual query"); XCTAssertEqual(word?.display, "display title")
        let video = try XCTUnwrap(recorder.requests.first { Self.queryValues(for: $0)["search_type"] == "video" })
        XCTAssertEqual(Self.queryValues(for: video)["duration"], "3")
        XCTAssertEqual(Self.queryValues(for: video)["order"], "click")
        let live = try XCTUnwrap(recorder.requests.first { Self.queryValues(for: $0)["search_type"] == "live_room" })
        XCTAssertEqual(Self.queryValues(for: live)["page"], "2"); XCTAssertNil(Self.queryValues(for: live)["duration"])
        XCTAssertNotNil(Self.queryValues(for: live)["w_rid"])
    }

    @MainActor
    func testTripleUsesPGCAndUGCEndpointsAndNeverRetriesAmbiguousCoinWrites() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            return Self.response(for: request, body: #"{"code":0,"data":{"like":true,"coin":true,"fav":true,"multiply":2}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=triple; DedeUserID=1001; bili_jct=triple-csrf")
        let video = try JSONDecoder().decode(VideoItem.self, from: Data(#"{"bvid":"BVtest","aid":99,"title":"UGC"}"#.utf8))
        let pgc = try JSONDecoder().decode(VideoItem.self, from: Data(#"{"bvid":"ep77","aid":99,"title":"PGC","pgcEpisodeID":77}"#.utf8))
        let identity = PiliAccountIdentity(api.requestSnapshot(purpose: .interaction))
        let result = try await api.piliTriple(video: video, identity: identity)
        XCTAssertEqual(result["coin"].piliInt, 1)
        _ = try await api.piliTriple(video: pgc, identity: identity)
        XCTAssertEqual(recorder.requests.map { $0.url!.path }, ["/x/web-interface/archive/like/triple", "/pgc/season/episode/like/triple"])
        XCTAssertEqual(formValues(in: recorder.requests[0])["aid"], "99")
        XCTAssertEqual(formValues(in: recorder.requests[1])["ep_id"], "77")
        XCTAssertEqual(formValues(in: recorder.requests[1])["csrf"], "triple-csrf")
        let failures = RequestContractRecorder()
        RequestContractURLProtocol.install { request in failures.record(request); throw URLError(.networkConnectionLost) }
        do { _ = try await api.piliTriple(video: video, identity: identity); XCTFail() }
        catch { XCTAssertEqual(failures.requests.count, 1) }
        do { _ = try await api.piliTriple(video: video, identity: .init(mid: 1001, version: -1)); XCTFail() }
        catch { XCTAssertEqual(failures.requests.count, 1, "Stale identity must never submit a financial mutation") }
    }

    @MainActor
    func testLiveReplyShieldReportRankingAndFollowingContracts() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(for: request, body: #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/abc.png","sub_url":"https://i.example.com/def.png"}}}"#)
            }
            if request.url?.path == "/xlive/web-ucenter/user/following" {
                return Self.response(for: request, body: #"{"code":0,"data":{"totalPage":3,"list":[{"roomid":99,"live_status":1,"room_cover":"//i.example.com/live.jpg"},{"roomid":100,"live_status":0}]}}"#)
            }
            return Self.response(for: request, body: #"{"code":0,"data":{}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=live; DedeUserID=1001; bili_jct=live-csrf")
        let identity = PiliAccountIdentity(api.requestSnapshot())
        let item = try XCTUnwrap(LiveDanmakuService.parsedItems(for: PiliLiveChatTests.message(), roomID: 9, startDate: .now).first)
        try await api.piliSendLive(roomID: 9, message: "reply", emote: false, identity: identity, reply: item.liveMetadata)
        try await api.piliLiveShieldKeyword("sale", remove: false, roomID: 9, identity: identity)
        try await api.piliLiveShieldUser(uid: 42, remove: true, roomID: 9, identity: identity)
        try await api.piliReportLiveMessage(item, roomID: 9, reason: "\u{5783}\u{573e}\u{5e7f}\u{544a}", reasonID: 3, identity: identity)
        _ = try await api.piliLiveRanks(roomID: 9, ownerID: 10, type: "weekly_rank", page: 2)
        let followed = try await api.piliFollowedLiveRooms(page: 2, identity: identity)
        XCTAssertTrue(followed.more); XCTAssertEqual(followed.rooms.map(\.roomID), [99])
        XCTAssertEqual(followed.rooms.first?.cover, "//i.example.com/live.jpg")
        let writes = recorder.requests.filter { $0.httpMethod == "POST" }
        XCTAssertEqual(writes.count, 4)
        XCTAssertEqual(formValues(in: writes[0])["reply_mid"], "42"); XCTAssertEqual(formValues(in: writes[0])["replay_dmid"], "9876543210987")
        XCTAssertTrue(writes[1].url!.path.hasSuffix("AddShieldKeyword")); XCTAssertEqual(formValues(in: writes[1])["keyword"], "sale")
        XCTAssertEqual(formValues(in: writes[2])["type"], "0")
        XCTAssertEqual(formValues(in: writes[3])["sign"], "report-signature"); XCTAssertEqual(formValues(in: writes[3])["reason_id"], "3")
        for request in writes { XCTAssertEqual(formValues(in: request)["csrf_token"], "live-csrf") }
        let rank = try XCTUnwrap(recorder.requests.first { $0.url?.path.contains("queryContributionRank") == true })
        XCTAssertEqual(Self.queryValues(for: rank)["switch"], "current_week_rank"); XCTAssertEqual(Self.queryValues(for: rank)["page"], "2")
    }

    @MainActor
    func testPGCCatalogueUsesServerFiltersAndTimelineResultEnvelope() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch request.url?.path {
            case "/pgc/season/index/condition":
                return Self.response(for: request, body: #"{"code":0,"data":{"order":[{"field":"3","name":"\#u{8ffd}\#u{756a}\#u{4eba}\#u{6570}"}],"filter":[{"field":"area","name":"\#u{5730}\#u{533a}","values":[{"keyword":"-1","name":"\#u{5168}\#u{90e8}"},{"keyword":"2","name":"\#u{65e5}\#u{672c}"}]}]}}"#)
            case "/pgc/season/index/result":
                return Self.response(for: request, body: #"{"code":0,"data":{"has_next":1,"list":[{"season_id":42,"title":"\#u{756a}\#u{5267}","cover":"https://i0.hdslb.com/test.jpg","index_show":"\#u{66f4}\#u{65b0}\#u{81f3}\#u{7b2c} 4 \#u{8bdd}"}]}}"#)
            case "/pgc/web/timeline":
                return Self.response(for: request, body: #"{"code":0,"result":[{"date":"10-06","is_today":1,"episodes":[{"episode_id":9,"season_id":42,"title":"\#u{756a}\#u{5267}","pub_time":"18:00","pub_index":"\#u{7b2c} 4 \#u{8bdd}"}]}]}"#)
            default: return Self.response(for: request, body: #"{"code":-404}"#)
            }
        }
        let api = try makeAPI(cookieHeader: "")
        let conditions = try await api.piliPGCConditions(type: 1)
        XCTAssertEqual(conditions.defaults["area"], "-1")
        XCTAssertEqual(conditions.defaults["order"], "3")
        let result = try await api.piliPGCCatalogue(type: 1, page: 2, filters: ["area": "2", "order": "3", "sort": "0"])
        XCTAssertEqual(result.items.first?.seasonID, 42); XCTAssertTrue(result.more)
        let url = try XCTUnwrap(recorder.request?.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for (name, value) in ["area": "2", "page": "2", "pagesize": "21", "season_type": "1", "type": "0"] {
            XCTAssertTrue(query.contains(.init(name: name, value: value)))
        }
        let timeline = try await api.piliPGCTimeline(type: 1)
        XCTAssertEqual(timeline.first?.title, "10-06 · \u{4eca}\u{5929}")
        XCTAssertEqual(timeline.first?.episodes.first?.id, 9)
    }

    @MainActor
    func testSponsorCommunityPreservesAllActionsAndUsesUnauthenticatedSingleWrites() async throws {
        let recorder = RequestContractRecorder()
        let counter = RequestContractCounter()
        RequestContractURLProtocol.install { request in
            _ = counter.increment(); recorder.record(request)
            let body = request.httpMethod == "POST" ? "{}" : #"[{"UUID":"skip","cid":12,"category":"sponsor","actionType":"skip","segment":[1,4]},{"UUID":"mute","category":"sponsor","actionType":"mute","segment":[4,8]},{"UUID":"full","category":"exclusive_access","actionType":"full","segment":[0,90]},{"UUID":"poi","category":"poi_highlight","actionType":"poi","segment":[20,20]},{"UUID":"invalid","category":"sponsor","actionType":"skip","segment":[8,2]}]"#
            return Self.response(for: request, body: body)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestContractURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = SponsorBlockService(baseURL: URL(string: "https://community.invalid")!, session: session)
        let segments = try await service.fetchSkipSegments(bvid: "BV-test", cid: 12)
        XCTAssertEqual(Set(segments.map(\.actionType)), ["skip", "mute", "full", "poi"])
        try await service.vote(uuid: "skip", type: 1, userID: "community-id")
        let vote = try XCTUnwrap(recorder.request)
        XCTAssertEqual(vote.httpMethod, "POST")
        XCTAssertEqual(vote.url?.path, "/api/voteOnSponsorTime")
        let query = URLComponents(url: vote.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(query.contains(.init(name: "UUID", value: "skip")))
        XCTAssertTrue(query.contains(.init(name: "userID", value: "community-id")))
        XCTAssertEqual(vote.value(forHTTPHeaderField: "Cookie") ?? "", "")
        try await service.submit(bvid: "BV-test", cid: 12, duration: 90, start: 8, end: 20, category: .sponsor, action: "mute", userID: "community-id")
        let submission = try XCTUnwrap(recorder.request)
        XCTAssertEqual(submission.url?.path, "/api/skipSegments")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(requestBodyData(from: submission))) as? [String: Any])
        XCTAssertEqual(body["cid"] as? String, "12")
        XCTAssertEqual(body["videoDuration"] as? Double, 90)
        let payload = try XCTUnwrap((body["segments"] as? [[String: Any]])?.first)
        XCTAssertEqual(payload["actionType"] as? String, "mute")
        XCTAssertEqual(payload["segment"] as? [Double], [8, 20])
        do {
            try await service.submit(bvid: "BV-test", cid: 12, duration: 90, start: 50, end: 10, category: .sponsor, action: "skip", userID: "community-id")
            XCTFail("Invalid interval must never be sent")
        } catch { }
        XCTAssertEqual(counter.currentValue, 3)
    }

    @MainActor
    func testSpacePrivacyAndPGCReviewsPreserveWireSemanticsAndDoNotRetryWrites() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/space/setting/app" {
                return Self.response(for: request, body: #"{"code":0,"data":{"privacy":{"disable_following":1,"fav_video":0,"future":9}}}"#)
            }
            if request.url?.path == "/pgc/review/long/list" {
                return Self.response(for: request, body: #"{"code":0,"data":{"next":"cursor2","count":0,"list":[{"review_id":42,"article_id":50,"score":10,"author":{"mid":9,"uname":"\#u{4f5c}\#u{8005}"},"content":"\#u{957f}\#u{8bc4}","stat":{"likes":3}}]}}"#)
            }
            return Self.response(for: request, body: #"{"code":0,"data":{}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=utilities; DedeUserID=1001; bili_jct=utilities-csrf")
        let identity = PiliAccountIdentity(api.requestSnapshot())
        let values = try await api.piliSpacePrivacy(identity: identity)
        XCTAssertEqual(values, ["disable_following": 1, "fav_video": 0])
        try await api.piliSaveSpacePrivacy(["disable_following": 0], identity: identity)
        var request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/space/privacy/batch/modify")
        var fields = formValues(in: request)
        XCTAssertEqual(fields["disable_following"], "0"); XCTAssertNil(fields["fav_video"])
        XCTAssertEqual(fields["csrf"], "utilities-csrf")
        let reviews = try await api.piliPGCReviews(mediaID: 4, long: true, latest: true, cursor: "cursor1")
        XCTAssertNil(reviews.total); XCTAssertEqual(reviews.next, "cursor2"); XCTAssertEqual(reviews.items.first?.articleID, 50)
        try await api.piliMutatePGCReview(mediaID: 4, action: .save(id: nil, score: 8, text: "A+B", share: false), identity: identity)
        request = try XCTUnwrap(recorder.request); fields = formValues(in: request)
        XCTAssertEqual(request.url?.path, "/pgc/review/short/post")
        XCTAssertEqual(fields["content"], "A+B"); XCTAssertEqual(fields["score"], "8"); XCTAssertNil(fields["share_feed"])
        try await api.piliMutatePGCReview(mediaID: 4, action: .like(42), identity: identity)
        XCTAssertEqual(formValues(in: try XCTUnwrap(recorder.request))["review_type"], "2")
        do {
            try await api.piliSaveSpacePrivacy(["fav_video": 1], identity: .init(mid: 2, version: identity.version))
            XCTFail("An old account must not write privacy settings")
        } catch { }
        XCTAssertEqual(recorder.request?.url?.path, "/pgc/review/action/like")
    }

    @MainActor
    func testDiscoveryKeepsWeeklyNumbersRankingTypesAndPreciousPagination() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(for: request, body: #"{"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png","sub_url":"https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png"}}}"#)
            }
            if request.url?.path == "/x/web-interface/popular/series/list" {
                return Self.response(for: request, body: #"{"code":0,"data":{"list":[{"number":400,"name":"\#u{7b2c} 400 \#u{671f}"}]}}"#)
            }
            if request.url?.path == "/pgc/web/rank/list" {
                return Self.response(for: request, body: #"{"code":0,"result":{"list":[{"season_id":3,"title":"\#u{756a}\#u{5267}"}]}}"#)
            }
            return Self.response(for: request, body: #"{"code":0,"data":{"list":[{"aid":1,"bvid":"BV1test","title":"\#u{6bcf}\#u{5468}\#u{89c6}\#u{9891}"}]}}"#)
        }
        let api = try makeAPI(cookieHeader: "")
        let issues = try await api.piliWeeklyIssues(); XCTAssertEqual(issues.first?.id, 400)
        let weekly = try await api.piliDiscoveryVideos(weekly: 400)
        XCTAssertEqual(weekly.videos.first?.title, "\u{6bcf}\u{5468}\u{89c6}\u{9891}"); XCTAssertFalse(weekly.more)
        var query = URLComponents(url: try XCTUnwrap(recorder.request?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(query.contains(.init(name: "number", value: "400")))
        XCTAssertTrue(query.contains { $0.name == "w_rid" })
        let ranks = try await api.piliDiscoveryVideos(rank: PiliRankCategory.all[1]); XCTAssertEqual(ranks.media.first?.seasonID, 3)
        _ = try await api.piliDiscoveryVideos(preciousPage: 2)
        query = URLComponents(url: try XCTUnwrap(recorder.request?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(query.contains(.init(name: "page", value: "2"))); XCTAssertTrue(query.contains(.init(name: "page_size", value: "100")))
    }

    @MainActor
    func testAUAudioReadsUseListenerProtocolAndAnonymousPlaybackIdentity() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path.hasSuffix("/PlayURL") == true {
                var audio = PiliProtoMessage(); audio.set(1, integer: 30280); audio.set(2, string: "https://audio.example.com/song.m4a")
                var dash = PiliProtoMessage(); dash.set(1, integer: 60); dash.set(3, messages: [audio])
                var info = PiliProtoMessage(); info.set(5, message: dash)
                var entry = PiliProtoMessage(); entry.set(1, integer: 123); entry.set(2, message: info)
                var response = PiliProtoMessage(); response.set(4, messages: [entry])
                return Self.response(for: request, data: BiliListenerPlaylistCodec.frame(response.data))
            }
            var response = PiliProtoMessage(); response.set(3, integer: 1)
            return Self.response(for: request, data: BiliListenerPlaylistCodec.frame(response.data))
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=secret; DedeUserID=1001; buvid3=device", accessKey: "secret-key", configure: { _, library in library.setIncognitoModeEnabled(true) })
        let result = try await api.piliAudioPlaylist(id: 123, order: .reverse)
        XCTAssertNil(result.next)
        let sources = try await api.piliAudioSources(PiliAudioCodec.item(123)); XCTAssertEqual(sources.first?.duration, 60)
        XCTAssertTrue(recorder.requests.allSatisfy { !($0.value(forHTTPHeaderField: "Cookie") ?? "").contains("secret") })
        XCTAssertTrue(recorder.requests.allSatisfy { !($0.value(forHTTPHeaderField: "authorization") ?? "").contains("secret-key") })
        let request = try XCTUnwrap(recorder.requests.first)
        let body = try PiliProtoMessage(data: BiliListenerPlaylistCodec.unframe(try XCTUnwrap(requestBodyData(from: request))))
        XCTAssertEqual(try body.message(3).integer(1), 3); XCTAssertEqual(try body.message(3).integer(3), 123)
        XCTAssertEqual(try body.message(7).integer(1), 2)
    }

    @MainActor
    func testCommunityDetailsAndMemberAudioKeepSeparateEndpointNamespaces() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(for: request, body: #"{"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png","sub_url":"https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png"}}}"#)
            }
            if request.url?.path == "/audio/music-service/web/song/upper" {
                return Self.response(for: request, body: #"{"code":0,"data":{"totalSize":1,"data":[{"id":123,"title":"AU","cover":"https://i0.hdslb.com/a.jpg"}]}}"#)
            }
            if request.url?.path == "/x/esports/match/info" { return Self.response(for: request, body: #"{"code":0,"data":{"contest":{"home_score":1,"away_score":2}}}"#) }
            return Self.response(for: request, body: #"{"code":0,"data":{"music_title":"\#u{6d4b}\#u{8bd5}\#u{97f3}\#u{4e50}"}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=s; bili_jct=csrf; DedeUserID=1001")
        let audio = try await api.piliMemberExtras(.audio, mid: 17, page: 1)
        XCTAssertEqual(audio.items.first?["id"].piliInt, 123); XCTAssertFalse(audio.more)
        XCTAssertEqual(recorder.request?.url?.host, "api.bilibili.com")
        let match = try await api.piliMatch(123); XCTAssertEqual(match["away_score"].piliInt, 2)
        _ = try await api.piliBubble(id: "6", category: "7", sort: 2, page: 3)
        let query = URLComponents(url: try XCTUnwrap(recorder.request?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        for (key, value) in ["tribee_id": "6", "category_id": "7", "sort_type": "2", "page_num": "3"] { XCTAssertTrue(query.contains(.init(name: key, value: value))) }
        _ = try await api.piliMusic("MA10")
        XCTAssertEqual(recorder.request?.url?.path, "/x/copyright-music-publicity/bgm/detail")
        try await api.piliMusicWish("MA10", selected: false, identity: .init(api.requestSnapshot()))
        XCTAssertEqual(formValues(in: try XCTUnwrap(recorder.request))["state"], "1")
        XCTAssertEqual(formValues(in: try XCTUnwrap(recorder.request))["csrf"], "csrf")
    }

    @MainActor
    func testCollectedLibrariesUseOriginalPagingAndOpusNumericAction() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch request.url?.path {
            case "/x/space/bangumi/follow/list":
                return Self.response(for: request, body: #"{"code":0,"data":{"total":31,"list":[{"season_id":123,"title":"\#u{6d4b}\#u{8bd5}\#u{756a}\#u{5267}"}]}}"#)
            case "/x/topic/web/fav/list":
                return Self.response(for: request, body: #"{"code":0,"data":{"topic_list":{"page_info":{"total":1},"topic_items":[{"id":7,"name":"\#u{6d4b}\#u{8bd5}\#u{8bdd}\#u{9898}"}]}}}"#)
            case "/x/polymer/web-dynamic/v1/opus/feed/fav":
                return Self.response(for: request, body: #"{"code":0,"data":{"has_more":true,"items":[{"opus_id":"999","content":"\#u{6536}\#u{85cf}\#u{56fe}\#u{6587}"}]}}"#)
            default: return Self.response(for: request, body: #"{"code":0,"data":{}}"#)
            }
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=s; bili_jct=csrf; DedeUserID=1001"), identity = PiliAccountIdentity(api.requestSnapshot())
        let anime = try await api.piliCollectedContent(.anime, page: 2, status: 3, identity: identity)
        XCTAssertTrue(anime.more); XCTAssertEqual(anime.items.first?["season_id"].piliInt, 123)
        let query = URLComponents(url: try XCTUnwrap(recorder.request?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        for (name, value) in ["vmid": "1001", "type": "1", "pn": "2", "ps": "15", "follow_status": "3"] { XCTAssertTrue(query.contains(.init(name: name, value: value))) }
        let articles = try await api.piliCollectedContent(.articles, page: 1, identity: identity); XCTAssertTrue(articles.more)
        let topics = try await api.piliCollectedContent(.topics, page: 1, identity: identity); XCTAssertFalse(topics.more)
        try await api.piliOpusFavorite(id: "999", add: false, identity: identity)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/x/community/cosmo/interface/simple_action")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(requestBodyData(from: request))) as? [String: Any])
        XCTAssertEqual(json["action"] as? Int, 4)
        let entity = try XCTUnwrap(json["entity"] as? [String: Any]); XCTAssertEqual(entity["object_id_str"] as? String, "999")
        XCTAssertEqual((entity["type"] as? [String: Any])?["biz"] as? Int, 2)
        try await api.piliFollowStatus(ids: [3,1], status: 2, identity: identity)
        XCTAssertEqual(formValues(in: try XCTUnwrap(recorder.request))["season_id"], "1,3")
        let count = recorder.requests.count
        do { try await api.piliFollowStatus(ids: [-1], status: 2, identity: identity); XCTFail("Invalid season") } catch {}
        XCTAssertEqual(recorder.requests.count, count)
    }

    @MainActor
    func testVideoDanmakuRulesAndRecallUseOwnedIdentityAndSingleWrites() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            switch request.url?.path {
            case "/x/dm/filter/user": return Self.response(for: request, body: #"{"code":0,"data":{"rule":[{"id":7,"type":0,"filter":"\#u{5e7f}\#u{544a}"}]}}"#)
            case "/x/dm/filter/user/add": return Self.response(for: request, body: #"{"code":0,"data":{"id":8,"type":2,"filter":"884863d2"}}"#)
            default: return Self.response(for: request, body: #"{"code":0,"data":{}}"#)
            }
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=rules; DedeUserID=1001; bili_jct=rules-csrf")
        let identity = PiliAccountIdentity(api.requestSnapshot())
        let suite = "DanmakuRules.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PiliDanmakuRulesStore(defaults: defaults)
        await store.refresh(api: api)
        XCTAssertEqual(store.rules.map(\.id), [7])
        try await store.add(text: "123", type: 2, api: api, identity: identity)
        let add = try XCTUnwrap(recorder.requests.first { $0.url?.path == "/x/dm/filter/user/add" })
        XCTAssertEqual(formValues(in: add)["filter"], "884863d2")
        XCTAssertEqual(formValues(in: add)["csrf"], "rules-csrf")
        let item = DanmakuItem(id: "local", time: 1, mode: 1, fontSize: 25, color: 0xffffff, text: "\u{81ea}\u{5df1}\u{7684}\u{5f39}\u{5e55}",
            serverID: "9007199254740993", cid: 99, senderHash: PiliDanmakuRule.userHash(1001))
        try await api.recallPiliDanmaku(item, identity: identity)
        let recall = try XCTUnwrap(recorder.requests.last { $0.url?.path == "/x/dm/recall" })
        XCTAssertEqual(formValues(in: recall)["dmid"], "9007199254740993")
        XCTAssertEqual(formValues(in: recall)["cid"], "99")
        store.didRecall(item, identity: identity)
        XCTAssertTrue(store.filter([item], identity: identity).isEmpty)
        let foreign = DanmakuItem(id: "foreign", time: 1, mode: 1, fontSize: 25, color: 0xffffff, text: "\u{5176}\u{4ed6}\u{7528}\u{6237}", serverID: "77", cid: 99, senderHash: "884863d2")
        do { try await api.recallPiliDanmaku(foreign, identity: identity); XCTFail("Must reject another sender") } catch {}
        XCTAssertEqual(recorder.requests.filter { $0.url?.path == "/x/dm/recall" }.count, 1)
        let reloaded = PiliDanmakuRulesStore(defaults: defaults); reloaded.synchronize(api: api)
        XCTAssertEqual(reloaded.rules.map(\.id), [7, 8])
        try api.sessionStore.saveLoginCookies(["SESSDATA": "other", "DedeUserID": "2002", "bili_jct": "other-csrf"], credentialKind: .web)
        reloaded.synchronize(api: api)
        XCTAssertTrue(reloaded.rules.isEmpty, "Rules must not leak across accounts")
        do { try await reloaded.add(text: "\u{65e7}\u{8d26}\u{53f7}", type: 0, api: api, identity: identity); XCTFail("Stale account") } catch {}
        XCTAssertEqual(recorder.requests.filter { $0.url?.path == "/x/dm/filter/user/add" }.count, 1)
    }

    @MainActor
    func testFailedDanmakuRuleDeletionKeepsRulesAndDoesNotRetry() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/dm/filter/user" { return Self.response(for: request, body: #"{"code":0,"data":{"rule":[{"id":7,"type":0,"filter":"\#u{5e7f}\#u{544a}"}]}}"#) }
            return Self.response(for: request, body: #"{"code":-403,"message":"\#u{62d2}\#u{7edd}\#u{5220}\#u{9664}"}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=rules; DedeUserID=1001; bili_jct=rules-csrf")
        let store = PiliDanmakuRulesStore(defaults: try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)))
        await store.refresh(api: api)
        do { try await store.remove(try XCTUnwrap(store.rules.first), api: api, identity: PiliAccountIdentity(api.requestSnapshot())); XCTFail("Expected rejection") } catch {}
        XCTAssertEqual(store.rules.map(\.id), [7])
        XCTAssertEqual(recorder.requests.filter { $0.url?.path == "/x/dm/filter/user/del" }.count, 1)
    }

    @MainActor
    func testRecommendationFeedbackIsSignedUncachedAndPreservesReasonKind() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in recorder.record(request); return Self.response(for: request, body: #"{"code":0,"data":{}}"#) }
        let api = try makeAPI(cookieHeader: "SESSDATA=feed; DedeUserID=1001; bili_jct=feed-csrf", accessKey: "feed-access")
        let video = try XCTUnwrap(JSONDecoder().decode(RecommendFeedItem.self, from: Data(#"{"param":"123","title":"\#u{6d4b}\#u{8bd5}","card_goto":"av","three_point_v2":[{"type":"feedback","reasons":[{"id":7,"name":"\#u{6807}\#u{9898}\#u{95ee}\#u{9898}"}]}]}"#.utf8)).asVideoItem())
        let reason = try XCTUnwrap(video.piliRecommendation?.reasons.first), identity = PiliAccountIdentity(api.requestSnapshot())
        try await api.piliFeedFeedback(video: video, reason: reason, identity: identity)
        try await api.piliFeedFeedback(video: video, reason: reason, identity: identity)
        let requests = recorder.requests.filter { $0.url?.path == "/x/feed/dislike" }
        XCTAssertEqual(requests.count, 2, "Each user submission must reach the server, never a GET cache")
        let request = try XCTUnwrap(requests.first)
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.host, "app.bilibili.com")
        for (key, value) in ["id": "123", "goto": "av", "feedback_id": "7", "access_key": "feed-access"] {
            XCTAssertTrue(query.contains(.init(name: key, value: value)))
        }
        XCTAssertFalse(query.contains { $0.name == "reason_id" }); XCTAssertTrue(query.contains { $0.name == "sign" })
        do { try await api.piliFeedFeedback(video: video, reason: .init(value: 999, name: "\u{4f2a}\u{9020}", kind: "dislike"), identity: identity); XCTFail("Unknown reason") } catch {}
        XCTAssertEqual(recorder.requests.filter { $0.url?.path == "/x/feed/dislike" }.count, 2)
    }

    @MainActor
    func testVideoDislikeAndLiveFavoriteOrderingHaveSeparateEndpoints() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/v2/view" { return Self.response(for: request, body: #"{"code":0,"data":{"req_user":{"dislike":1}}}"#) }
            if request.url?.path.hasSuffix("get_fav_tag") == true { return Self.response(for: request, body: #"{"code":0,"data":{"tags":[{"id":3,"parent_id":1,"name":"A"},{"id":5,"parent_id":2,"name":"B"}]}}"#) }
            return Self.response(for: request, body: #"{"code":0,"data":{}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=app; DedeUserID=1001; bili_jct=app-csrf", accessKey: "app-access")
        let identity = PiliAccountIdentity(api.requestSnapshot())
        let disliked = try await api.piliVideoDisliked(aid: 123, identity: identity); XCTAssertTrue(disliked)
        try await api.piliDislikeVideo(aid: 123, dislike: false, identity: identity)
        let dislike = try XCTUnwrap(recorder.request)
        XCTAssertEqual(dislike.url?.path, "/x/v2/view/dislike")
        XCTAssertEqual(dislike.httpMethod, "POST"); XCTAssertEqual(formValues(in: dislike)["dislike"], "0")
        let areas = try await api.piliLiveFavoriteAreas(identity: identity)
        XCTAssertEqual(areas.map(\.id), [3, 5])
        try await api.setPiliLiveFavoriteAreas(Array(areas.reversed()), identity: identity)
        let save = try XCTUnwrap(recorder.request)
        XCTAssertEqual(save.url?.host, "api.live.bilibili.com")
        XCTAssertEqual(save.url?.path, "/xlive/app-interface/v2/second/set_fav_tag")
        XCTAssertEqual(formValues(in: save)["tags"], "5,3")
        XCTAssertEqual(formValues(in: save)["access_key"], "app-access")
        XCTAssertNotNil(formValues(in: save)["sign"])
    }

    @MainActor
    func testAIConclusionSignsCurrentPartAndPropagatesPlatformUnavailable() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            if request.url?.path == "/x/web-interface/nav" {
                return Self.response(for: request, body: #"{"code":0,"data":{"wbi_img":{"img_url":"https://i.example.com/7cd084941338484aae1ad9425b84077c.png","sub_url":"https://i.example.com/4932caff0ff746eab6f01bf08b70ac45.png"}}}"#)
            }
            recorder.record(request)
            return Self.response(for: request, body: #"{"code":0,"data":{"code":-1,"message":"\#u{6682}\#u{65e0}\#u{603b}\#u{7ed3}"}}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=summary; DedeUserID=1001")
        let video = try JSONDecoder().decode(VideoItem.self, from: Data(#"{"bvid":"BVtest","title":"\#u{6d4b}\#u{8bd5}","owner":{"mid":42,"name":"UP"}}"#.utf8))
        do { _ = try await api.piliAIConclusion(video: video, cid: 99, identity: PiliAccountIdentity(api.requestSnapshot())); XCTFail("Unavailable summary") }
        catch { XCTAssertTrue(error.localizedDescription.contains("\u{6682}\u{65e0}\u{603b}\u{7ed3}")) }
        let request = try XCTUnwrap(recorder.requests.first { $0.url?.path == "/x/web-interface/view/conclusion/get" })
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        for (key, value) in ["bvid": "BVtest", "cid": "99", "up_mid": "42"] { XCTAssertTrue(query.contains(.init(name: key, value: value))) }
        XCTAssertTrue(query.contains { $0.name == "w_rid" }); XCTAssertTrue(query.contains { $0.name == "wts" })
    }

    @MainActor
    func testQuickFavoriteOnlyRemovesConfiguredFolderAndPreservesOtherMemberships() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/v3/fav/folder/created/list-all" {
                return Self.response(for: request, body: #"{"code":0,"data":{"list":[{"id":7,"title":"\#u{9ed8}\#u{8ba4}","fav_state":1},{"id":8,"title":"\#u{5176}\#u{4ed6}","fav_state":1}]}}"#)
            }
            if request.url?.path == "/x/v3/fav/resource/deal" { return Self.response(for: request, body: #"{"code":0}"#) }
            return Self.response(for: request, body: #"{"code":-404,"message":"No metadata in fixture"}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=fav; DedeUserID=1001; bili_jct=fav-csrf")
        api.libraryStore.setQuickFavoriteFolder(7, account: 1001)
        let video = try JSONDecoder().decode(VideoItem.self, from: Data(#"{"bvid":"BVtest","aid":123,"title":"\#u{6d4b}\#u{8bd5}","cid":99}"#.utf8))
        let model = VideoDetailViewModel(seedVideo: video, api: api, libraryStore: api.libraryStore,
            sessionStore: api.sessionStore, sponsorBlockService: SponsorBlockService())
        let handled = await model.quickFavoriteIfConfigured()
        XCTAssertTrue(handled)
        XCTAssertTrue(model.interactionState.isFavorited, "The other folder still contains the video")
        let request = try XCTUnwrap(recorder.requests.first { $0.url?.path == "/x/v3/fav/resource/deal" })
        XCTAssertEqual(formValues(in: request)["add_media_ids"], "")
        XCTAssertEqual(formValues(in: request)["del_media_ids"], "7")
        XCTAssertEqual(formValues(in: request)["csrf"], "fav-csrf")
        XCTAssertEqual(recorder.requests.filter { $0.url?.path == "/x/v3/fav/resource/deal" }.count, 1)
    }

    @MainActor
    func testVideoDislikeRejectsMainIdentityWhenAnotherInteractionAccountIsSelected() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in recorder.record(request); return Self.response(for: request, body: #"{"code":0}"#) }
        let api = try makeAPI(cookieHeader: "SESSDATA=main; DedeUserID=1001; bili_jct=main-csrf", accessKey: "main-access", configure: { session, library in
            _ = try session.saveAdditionalAccount([Self.makeCookie(name: "DedeUserID", value: "2002"),
                Self.makeCookie(name: "SESSDATA", value: "interaction"), Self.makeCookie(name: "bili_jct", value: "interaction-csrf")])
            try session.selectInteractionAccount(mid: 2002); library.setMultiAccountExperimentEnabled(true)
        })
        do { try await api.piliDislikeVideo(aid: 123, dislike: true, identity: PiliAccountIdentity(api.requestSnapshot())); XCTFail("Wrong account") } catch {}
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    @MainActor
    func testMissingQuickFavoriteFolderFallsBackWithFreshFolderListAndNoWrite() async throws {
        let recorder = RequestContractRecorder()
        RequestContractURLProtocol.install { request in
            recorder.record(request)
            if request.url?.path == "/x/v3/fav/folder/created/list-all" {
                return Self.response(for: request, body: #"{"code":0,"data":{"list":[{"id":8,"title":"\#u{5269}\#u{4f59}\#u{6536}\#u{85cf}\#u{5939}","fav_state":0}]}}"#)
            }
            return Self.response(for: request, body: #"{"code":-404}"#)
        }
        let api = try makeAPI(cookieHeader: "SESSDATA=fav; DedeUserID=1001; bili_jct=fav-csrf")
        api.libraryStore.setQuickFavoriteFolder(7, account: 1001)
        let video = try JSONDecoder().decode(VideoItem.self, from: Data(#"{"bvid":"BVtest","aid":123,"title":"\#u{6d4b}\#u{8bd5}","cid":99}"#.utf8))
        let model = VideoDetailViewModel(seedVideo: video, api: api, libraryStore: api.libraryStore,
            sessionStore: api.sessionStore, sponsorBlockService: SponsorBlockService())
        model.favoriteFolders = [try JSONDecoder().decode(FavoriteFolder.self, from: Data(#"{"id":7,"title":"\#u{5df2}\#u{5220}\#u{9664}"}"#.utf8))]
        let handled = await model.quickFavoriteIfConfigured()
        XCTAssertFalse(handled)
        XCTAssertEqual(api.libraryStore.quickFavoriteFolder(account: 1001), 0)
        XCTAssertEqual(model.favoriteFolders.map(\.id), [8])
        XCTAssertFalse(recorder.requests.contains { $0.httpMethod == "POST" })
    }

    @MainActor
    func testNewAccountsCanStartWithEmptyDanmakuAndLiveFavorites() async throws {
        RequestContractURLProtocol.install { request in Self.response(for: request, body: #"{"code":0,"data":{}}"#) }
        let api = try makeAPI(cookieHeader: "SESSDATA=empty; DedeUserID=1001; bili_jct=empty-csrf", accessKey: "empty-access")
        let identity = PiliAccountIdentity(api.requestSnapshot())
        let rules = try await api.piliDanmakuRules(identity: identity)
        let areas = try await api.piliLiveFavoriteAreas(identity: identity)
        XCTAssertTrue(rules.isEmpty); XCTAssertTrue(areas.isEmpty)
    }

    @MainActor
    private func makeAPI(
        cookieHeader: String,
        accessKey: String? = nil,
        playURLCache: PlayURLCache = .shared,
        guestModeEnabled: Bool = false,
        recommendSource: HomeRecommendFeedSourcePreference = .web,
        configure: ((SessionStore, LibraryStore) throws -> Void)? = nil,
        webPagePlayInfoStreamFetch:
            @escaping @Sendable (URLRequest, Float) async throws
            -> BiliWebPagePlayInfoStreamResult = { request, priority in
                try await BiliWebPagePlayInfoStreamingSession.shared.fetch(
                    request: request,
                    priority: priority
                )
            }
    ) throws -> BiliAPIClient {
        let keychainService = "BiliAPIClientRequestContractTests.\(UUID().uuidString)"
        let keychain = KeychainStore(service: keychainService)
        let cookieValues = cookieHeader.split(separator: ";").reduce(into: [String: String]()) { values, item in
            let parts = item.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return }
            values[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(
                in: .whitespaces)
        }
        try keychain.save(cookieHeader, for: "LOGIN_COOKIE_HEADER")
        try keychain.save(cookieValues["SESSDATA"] ?? "", for: "SESSDATA")
        if let accessKey {
            try keychain.save(accessKey, for: "ACCESS_KEY")
        }
        try keychain.save(LoginCredentialKind.web.rawValue, for: "LOGIN_CREDENTIAL_KIND")

        let sessionStore = SessionStore(keychain: keychain)
        if cookieValues["DedeUserID"] != nil {
            try sessionStore.saveLoginCookies(cookieValues, credentialKind: .web)
        }
        let libraryStore = LibraryStore(userDefaults: UserDefaults(suiteName: keychainService)!)
        libraryStore.setGuestModeEnabled(guestModeEnabled)
        libraryStore.setHomeRecommendFeedSourcePreference(recommendSource)
        try configure?(sessionStore, libraryStore)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestContractURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        return BiliAPIClient(
            session: session,
            sessionStore: sessionStore,
            libraryStore: libraryStore,
            homeRecommendDiagnosticsStore: .shared,
            playURLCache: playURLCache,
            webPagePlayInfoStreamFetch: webPagePlayInfoStreamFetch
        )
    }

    private nonisolated static func response(for request: URLRequest, body: String) -> (HTTPURLResponse, Data) {
        response(for: request, data: Data(body.utf8))
    }

    private nonisolated static func makeCookie(name: String, value: String) -> HTTPCookie {
        HTTPCookie(
            properties: [
                .domain: ".bilibili.com",
                .path: "/",
                .name: name,
                .value: value,
                .secure: "TRUE",
            ]
        )!
    }

    private nonisolated static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        headerFields: [String: String] = ["Content-Type": "application/json"],
        data: Data
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        )!
        return (response, data)
    }

    private nonisolated static func protobufDanmakuSegmentData() -> Data {
        let element =
            protobufVarintField(1, value: 42)
            + protobufVarintField(2, value: 1_500)
            + protobufVarintField(3, value: 1)
            + protobufVarintField(4, value: 25)
            + protobufVarintField(5, value: 16_777_215)
            + protobufLengthDelimitedField(7, payload: Array("\u{5206}\u{6bb5}\u{5f39}\u{5e55}".utf8))
        return Data(protobufLengthDelimitedField(1, payload: element))
    }

    private nonisolated static func protobufVarintField(_ fieldNumber: Int, value: UInt64) -> [UInt8] {
        protobufVarint(UInt64(fieldNumber << 3)) + protobufVarint(value)
    }

    private nonisolated static func protobufLengthDelimitedField(_ fieldNumber: Int, payload: [UInt8]) -> [UInt8] {
        protobufVarint(UInt64((fieldNumber << 3) | 2))
            + protobufVarint(UInt64(payload.count))
            + payload
    }

    private nonisolated static func protobufVarint(_ value: UInt64) -> [UInt8] {
        var remaining = value
        var bytes = [UInt8]()
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 {
                byte |= 0x80
            }
            bytes.append(byte)
        } while remaining != 0
        return bytes
    }

    private nonisolated static func playableDASHResponse(
        quality: Int,
        acceptedQualities: [Int]? = nil
    ) -> String {
        let acceptedQualityList = (acceptedQualities ?? [quality])
            .map(String.init)
            .joined(separator: ",")
        return
            #"{"code":0,"data":{"quality":\#(quality),"accept_quality":[\#(acceptedQualityList)],"dash":{"video":[{"id":\#(quality),"base_url":"https://video.example.com/video.m4s","codecs":"avc1.640028","codecid":7,"mime_type":"video/mp4"}],"audio":[{"id":30280,"base_url":"https://audio.example.com/audio.m4s","codecs":"mp4a.40.2","mime_type":"audio/mp4"}]}}}"#
    }

    @MainActor
    private func startupSchedulerDiagnostics(
        for metricsID: String,
        containing expectedText: String
    ) async throws -> String {
        for _ in 0..<50 {
            let message = PlayerPerformanceStore.shared.session(for: metricsID)?.startupSchedulerMessage ?? ""
            if message.contains(expectedText) {
                return message
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return PlayerPerformanceStore.shared.session(for: metricsID)?.startupSchedulerMessage ?? ""
    }

    private nonisolated static func videoItemResponse(bvid: String, aid: Int) -> String {
        #"{"code":0,"data":{"bvid":"\#(bvid)","aid":\#(aid),"title":"\#u{89c6}\#u{9891}\#u{8be6}\#u{60c5}"}}"#
    }

    private func cookieValues(in header: String?) -> [String: String] {
        (header ?? "").split(separator: ";").reduce(into: [:]) { values, item in
            let pair = item.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { return }
            values[String(pair[0]).trimmingCharacters(in: .whitespaces)] = String(pair[1])
                .trimmingCharacters(in: .whitespaces)
        }
    }

    private nonisolated static func queryValues(in components: URLComponents) -> [String: String] {
        components.queryItems?.reduce(into: [:]) { values, item in
            values[item.name] = item.value ?? ""
        } ?? [:]
    }

    private nonisolated static func queryValues(for request: URLRequest) -> [String: String] {
        guard let url = request.url,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return [:] }
        return Self.queryValues(in: components)
    }

    private nonisolated static func queryValue(named name: String, in request: URLRequest) -> String? {
        guard let url = request.url,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return components.queryItems?.first(where: { $0.name == name })?.value
    }

    private func formValues(in request: URLRequest) -> [String: String] {
        guard let body = requestBodyData(from: request),
            let bodyString = String(data: body, encoding: .utf8),
            let components = URLComponents(string: "?\(bodyString)")
        else { return [:] }
        return Self.queryValues(in: components)
    }

    private func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class RequestContractRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests.last
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func record(_ request: URLRequest) {
        lock.lock()
        storedRequests.append(request)
        lock.unlock()
    }
}

private final class RequestContractCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    var currentValue: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private actor RequestContractAsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false
    private(set) var isWaiting = false

    func wait() async {
        guard !isReleased else { return }
        isWaiting = true
        await withCheckedContinuation { continuation in
            if isReleased {
                isWaiting = false
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
    }

    func release() {
        isReleased = true
        isWaiting = false
        continuation?.resume()
        continuation = nil
    }
}

private actor RequestContractCompletionFlag {
    private(set) var didComplete = false

    func markCompleted() {
        didComplete = true
    }
}

@MainActor
private final class BatchDownloadTestSink: PiliOfflineEnqueuing {
    var audioCIDs: [Int] = []
    var videoCount = 0
    func enqueue(video: VideoItem, pages: [VideoPage], variant: PlayVariant) throws -> Int {
        videoCount += pages.count
        return pages.count
    }
    func enqueueAudio(video: VideoItem, pages: [VideoPage], audio: VideoListenAudioVariant) throws -> Int {
        audioCIDs.append(contentsOf: pages.map(\.cid))
        return pages.count
    }
}

private final class RequestContractURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let state = HandlerState()

    static func install(_ handler: @escaping Handler) {
        state.install(handler)
    }

    static func reset() {
        state.reset()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        // This protocol is injected only into contract-test sessions. Never leak a
        // newly added CDN, WebDAV or LAN fixture request onto the real network.
        request.url?.scheme == "http" || request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let result: (HTTPURLResponse, Data) = try Self.currentHandler()(request)
            client?.urlProtocol(self, didReceive: result.0, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.1)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func currentHandler() throws -> Handler {
        try state.currentHandler()
    }

    private final class HandlerState: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: Handler?

        func install(_ handler: @escaping Handler) {
            lock.lock()
            self.handler = handler
            lock.unlock()
        }

        func reset() {
            lock.lock()
            handler = nil
            lock.unlock()
        }

        func currentHandler() throws -> Handler {
            lock.lock()
            let handler = self.handler
            lock.unlock()
            guard let handler else {
                throw URLError(.badServerResponse)
            }
            return handler
        }
    }
}
