//
//  ViewModel.swift
//  StackIT
//
//  Created by Jullian Mercier on 2020-07-25.
//

import Combine
import Foundation
import StackAPI
import SwiftUI

class QuestionsViewManager: ObservableObject {
    /// Published properties
    @Published var trending: Trending?
    @Published var tags: [TagSummary] = TagSummary.popular
    @Published var questionsSummary: [QuestionsSummary] = QuestionsSummary.placeholders
    @Published var questionsFilter: Set<QuestionsFilter> = []
    @Published var loadingSections: Set<QuestionsLoadingSection> = []
    @Published var showLoadMore: Bool = false
    @AppStorage("favoritesTags") private var favoritesTags: Data?
    @AppStorage("favoritesQuestions") var favoritesQuestions: Data?

    /// Private properties
    private var subscriptions = Set<AnyCancellable>()
    private var proxy: ViewManagerProxy
    
    /// Public properties
    var cachedQuestions: [QuestionsSummary] = []

    /// Subjects properties
    var resetSubject = PassthroughSubject<Void, Never>()
    var fetchTagsSubject = PassthroughSubject<AppSection, Never>()
    var fetchQuestionsSubject = CurrentValueSubject<AppSection, Never>(.questions)
    var toggleFavoriteQuestionSubject = PassthroughSubject<String, Never>()
    
    init(enableMock: Bool = false) {
        proxy = ViewManagerProxy(api: .init(enableMock: enableMock))
        bindFetchQuestions()
        bindFetchTags()
        bindToggleFavoriteQuestion()
        bindReset()
    }
    
    private func bindToggleFavoriteQuestion() {
        toggleFavoriteQuestionSubject
            .handleEvents(receiveOutput: { [weak self] questionId in
                self?.questionsSummary
                    .first(where: { $0.questionId == questionId })?
                    .isFavorite.toggle()
                self?.objectWillChange.send()
            })
            .map { [weak self] questionId in
                guard let self = self else { return Data() }
                var storedFavorites = self.favoritesQuestions.toArray()
                if let i = storedFavorites.firstIndex(where: { $0 == questionId }) {
                    storedFavorites.remove(at: i)
                } else {
                    storedFavorites.append(questionId)
                }
                            
                return storedFavorites.toData()
            }
            .assign(to: \.favoritesQuestions, on: self)
            .store(in: &subscriptions)
    }
    
    private func bindReset() {
        resetSubject
            .sink { [weak self] _ in
                self?.tags.forEach { $0.isFavorite = false }
                self?.fetchQuestionsSubject.send(AppSection.questions)
                self?.favoritesTags = nil
            }.store(in: &subscriptions)
    }
}

// MARK: - Posts-related bindings
extension QuestionsViewManager {
    private func bindFetchTags() {
        proxy.fetchTags()
            .map { [weak self] _ -> AnyPublisher<[TagSummary], Error> in
                guard let self = self else { return Just([]).setFailureType(to: Error.self).eraseToAnyPublisher() }
                return self.proxy.fetchTags()
            }
            .switchToLatest()
            .handleEvents(receiveSubscription: { [weak self] _ in
                self?.loadingSections.insert(.tags)
                self?.loadingSections.insert(.questions)
            }, receiveOutput: { [weak self] tags in
                self?.loadingSections.remove(.tags)
                self?.tags = tags
                self?.favoritesTags.toArray().forEach { favorite in
                    self?.tags.first(where: { $0.name == favorite })?.isFavorite.toggle()
                }
            })
            .replaceError(with: [])
            .sink { [weak self] _ in
                self?.fetchQuestionsSubject.send(.questions)
            }.store(in: &subscriptions)
    }
    
    private func bindFetchQuestions() {
        fetchQuestionsSubject
            .dropFirst()
            .handleEvents(receiveOutput: { [weak self] output in
                guard let self = self, case let .questions(subsection, action) = output else {
                    return
                }
                
                self.loadingSections.insert(.questions)
                
                switch subsection {
                case .trending(let selectedTrending):
                    self.trending = (selectedTrending == self.trending) ? nil: selectedTrending
                case .tag(let tag) where action == nil:
                    self.tags.first(where: { $0.name == tag.name })?.isFavorite.toggle()
                    self.favoritesTags = self.tags.filter(\.isFavorite).map(\.name).toData()
                case .search, .favorites:
                    self.tags.forEach { $0.isFavorite = false }
                default:
                    break
                }
            })
            .map { [weak self] section -> AnyPublisher<[QuestionsSummary], Error> in
                guard let self = self, case let .questions(subsection, action) = section else {
                    return Just([]).setFailureType(to: Error.self).eraseToAnyPublisher()
                }
                
                switch subsection {
                case .search(let keywords):
                    let outputEvent: (Search) -> Void = { [weak self] in
                        self?.showLoadMore = $0.hasMore
                    }
                    
                    return self.proxy.fetchQuestionsByKeywords(keywords: keywords,
                                                               action: action,
                                                               outputEvent: outputEvent)
                case .trending, .tag:
                    let outputEvent: (Questions) -> Void = { [weak self] in
                        self?.showLoadMore = $0.hasMore && $0.quotaRemaining > 0
                    }
                    
                    let selectedTags = self.tags.filter(\.isFavorite).map(\.name)
                    let selectedTrending = self.trending ?? .votes
                    
                    return self.proxy.fetchQuestionsWithFilters(tags: selectedTags,
                                                                trending: selectedTrending,
                                                                action: action,
                                                                outputEvent: outputEvent)
                case .favorites:
                    let outputEvent: (Questions) -> Void = { [weak self] in
                        self?.showLoadMore = $0.hasMore && $0.quotaRemaining > 0
                    }
                    
                    let favoritesQuestions = self.favoritesQuestions.toArray().joined(separator: ";")
                    return self.proxy.fetchQuestionsByIds(favoritesQuestions,
                                                          outputEvent: outputEvent,
                                                          action: action)
                    
                }
            }
            .switchToLatest()
            .replaceError(with: [])
            .map(updateFavorites)
            .assign(to: \.questionsSummary, on: self)
            .store(in: &subscriptions)
    }
    
    private func updateFavorites(in questions: [QuestionsSummary]) -> [QuestionsSummary] {
        let questionsSummary = questions
        let favoritesQuestionsIds = self.favoritesQuestions.toArray()
        questionsSummary.forEach {
            $0.isFavorite = favoritesQuestionsIds.contains($0.questionId)
        }
        
        return questionsSummary
    }
}

extension QuestionsViewManager {
    func updateQuestionsFilter(_ filter: QuestionsFilter) {
        if questionsFilter.contains(filter) {
            questionsFilter.remove(filter)
        } else {
            questionsFilter.insert(filter)
        }
        
        let filteredQuestions = questionsFilter.isEmpty ?
            cachedQuestions:
            cachedQuestions.filtered(by: questionsFilter)
        
        questionsSummary = filteredQuestions.isEmpty ? QuestionsSummary.empty: filteredQuestions
    }
}
