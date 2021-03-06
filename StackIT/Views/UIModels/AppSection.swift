//
//  AppSection.swift
//  StackIT
//
//  Created by Jullian Mercier on 2020-09-26.
//

import Foundation
import StackAPI

enum CommentsSection: Equatable {
    case question(QuestionsSummary)
    case answer(AnswersSummary)
}

enum AppSection: Equatable {
    case tags
    case questions(subsection: SubSection, Action? = nil)
    case answers(question: QuestionsSummary, Action? = nil)
    case comments(subsection: CommentsSection, Action? = nil)
    case account(subsection: AccountSection)
    case authentication(action: AuthenticationAction)
    
    func enablePaging() -> Self {
        switch self {
        case .questions(let subsection, let action):
            let pageCount = action?.pageCount ?? 1
            return .questions(subsection: subsection, .paging(count: pageCount + 1))
        case .answers(let question, let action):
            let pageCount = action?.pageCount ?? 1
            return .answers(question: question, .paging(count: pageCount + 1))
        default:
            return self
        }
    }
    
    func enableRefresh() -> Self {
        switch self {
        case .questions(let subsection, _):
            return .questions(subsection: subsection, .refresh)
        case .answers(let question, _):
            return .answers(question: question, .refresh)
        default:
            return self
        }
    }
}

extension AppSection {
    static let questions = AppSection.questions(subsection: .tag(tag: .init(name: .init())), nil)
}

enum SubSection: Equatable {
    case trending(trending: Trending)
    case tag(tag: TagSummary)
    case search(keywords: String)
    case favorites
}
