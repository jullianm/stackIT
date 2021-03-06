//
//  CommentsViewManager.swift
//  StackIT
//
//  Created by Jullian Mercier on 2020-09-30.
//

import Combine
import Foundation
import StackAPI

class CommentsViewManager: ObservableObject {
    /// Published properties
    @Published var commentsSummary: [CommentsSummary] = []
    @Published var loadingSections: Set<AnswersLoadingSection> = []
    @Published var showLoadMore: Bool = false

    /// Private properties
    private var subscriptions = Set<AnyCancellable>()
    private var proxy: ViewManagerProxy

    /// Subjects properties
    var fetchCommentsSubject = PassthroughSubject<AppSection, Never>()
    
    init(enableMock: Bool = false) {
        proxy = ViewManagerProxy(api: .init(enableMock: enableMock))
        bindFetchComments()
    }
}

// MARK: - Posts-related bindings
extension CommentsViewManager {
    private func bindFetchComments() {
        fetchCommentsSubject
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.loadingSections.insert(.comments)
            })
            .map { section -> AnyPublisher<[CommentsSummary], Error> in
                switch section {
                case let .comments(subsection, action):
                    switch subsection {
                    case .answer(let answer):
                        return self.proxy.fetchCommentsByAnswerId(answer.answerId,
                                                                  action: action)
                    case .question(let question):
                        return self.proxy.fetchCommentsByQuestionId(question.questionId,
                                                                    action: action)
                    }
                default:
                    return Just([]).setFailureType(to: Error.self).eraseToAnyPublisher()
                }
                
            }
            .switchToLatest()
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.loadingSections.remove(.comments)
            })
            .replaceError(with: [])
            .assign(to: \.commentsSummary, on: self)
            .store(in: &subscriptions)
    }
}

