//
// Mahlwerk
//
// Created by SAP Cloud Platform SDK for iOS Assistant application on 05/08/19
//

import SAPCommon
import SAPFiori
import SAPFioriFlows
import SAPFoundation
import WebKit

public class OnboardingFlowProvider: OnboardingFlowProviding {
    // MARK: – Properties

    public static let modalUIViewControllerPresenter = ModalUIViewControllerPresenter()
    public var runSynchingFlow = false

    // MARK: – Init

    public init() {}

    // MARK: – OnboardingFlowProvider

    public func flow(for _: OnboardingControlling, flowType: OnboardingFlow.FlowType, completionHandler: @escaping (OnboardingFlow?, Error?) -> Void) {
        switch flowType {
        case .onboard:
            completionHandler(self.onboardingFlow(), nil)
        case let .restore(onboardingID):
            completionHandler(self.restoringFlow(for: onboardingID), nil)
        case let .reset(onboardingID):
            completionHandler(self.resettingFlow(for: onboardingID), nil)
        @unknown default:
            break
        }
    }

    // MARK: – Internal

    func onboardingFlow() -> OnboardingFlow {
        let steps = self.onboardingSteps
        let context = OnboardingContext(presentationDelegate: OnboardingFlowProvider.modalUIViewControllerPresenter)
        let flow = OnboardingFlow(flowType: .onboard, context: context, steps: steps)
        return flow
    }

    func restoringFlow(for onboardingID: UUID) -> OnboardingFlow {
        var steps = [OnboardingStep]()
        if self.runSynchingFlow {
            steps = self.offlineSyncingSteps
            self.runSynchingFlow = false
        } else {
            steps = self.restoringSteps
        }
        var context = OnboardingContext(onboardingID: onboardingID, presentationDelegate: OnboardingFlowProvider.modalUIViewControllerPresenter)
        context.onboardingID = onboardingID
        let flow = OnboardingFlow(flowType: .restore(onboardingID: onboardingID), context: context, steps: steps)
        return flow
    }

    func resettingFlow(for onboardingID: UUID) -> OnboardingFlow {
        let steps = self.resettingSteps
        var context = OnboardingContext(onboardingID: onboardingID, presentationDelegate: OnboardingFlowProvider.modalUIViewControllerPresenter)
        context.onboardingID = onboardingID
        let flow = OnboardingFlow(flowType: .reset(onboardingID: onboardingID), context: context, steps: steps)
        return flow
    }

    // MARK: - Steps

    public var onboardingSteps: [OnboardingStep] {
        return [
            self.configuredWelcomeScreenStep(),
            CompositeStep(steps: SAPcpmsDefaultSteps.configuration),
            OAuth2AuthenticationStep(),
            CompositeStep(steps: SAPcpmsDefaultSteps.settingsDownload),
            CompositeStep(steps: SAPcpmsDefaultSteps.applyDuringOnboard),
            self.configuredUserConsentStep(),
            self.configuredStoreManagerStep(),
            ODataOnboardingStep(),
        ]
    }

    public var restoringSteps: [OnboardingStep] {
        return [
            self.configuredStoreManagerStep(),
            self.configuredWelcomeScreenStep(),
            CompositeStep(steps: SAPcpmsDefaultSteps.configuration),
            // allow offline onboarding
            self.configuredOAuth2AuthenticationStep(needsServerValidation: false),
            //CompositeStep(steps: SAPcpmsDefaultSteps.settingsDownload),
            CompositeStep(steps: SAPcpmsDefaultSteps.applyDuringRestore.map { ($0 as? PasscodePolicyApplyStep)?.defaultPasscodePolicy = nil; return $0 }),
            ODataOnboardingStep(),
        ]
    }

    public var offlineSyncingSteps: [OnboardingStep] {
        return [
            self.configuredWelcomeScreenStep(),
            CompositeStep(steps: SAPcpmsDefaultSteps.settingsDownload),
            CompositeStep(steps: SAPcpmsDefaultSteps.applyDuringRestore.map { ($0 as? PasscodePolicyApplyStep)?.defaultPasscodePolicy = nil; return $0 }),
        ]
    }

    public var resettingSteps: [OnboardingStep] {
        return self.onboardingSteps
    }

    // OAuth2AuthenticationStep
    private func configuredOAuth2AuthenticationStep(needsServerValidation: Bool) -> OAuth2AuthenticationStep {
        let presenter = FioriWKWebViewPresenter(webViewDelegate: self)
        let oAuth2AuthenticationStep = OAuth2AuthenticationStep(presenter: presenter)
        return oAuth2AuthenticationStep
    }
    
    // MARK: – Step configuration

    private func configuredWelcomeScreenStep() -> WelcomeScreenStep {
        let discoveryConfigurationTransformer = DiscoveryServiceConfigurationTransformer(applicationID: "<AppId>", authenticationPath: "<AppId>")
        let welcomeScreenStep = WelcomeScreenStep(transformer: discoveryConfigurationTransformer, providers: [FileConfigurationProvider()])

        welcomeScreenStep.welcomeScreenCustomizationHandler = { welcomeStepUI in
            welcomeStepUI.headlineLabel.text = "Mahlwerk Technician"
            welcomeStepUI.detailLabel.text = NSLocalizedString("keyWelcomeScreenMessage", value: "This application was generated by SAP Cloud Platform SDK for iOS Assistant", comment: "XMSG: Message on WelcomeScreen")
            welcomeStepUI.primaryActionButton.titleLabel?.text = NSLocalizedString("keyWelcomeScreenStartButton", value: "Start", comment: "XBUT: Title of start button on WelcomeScreen")

            // #warning("Remove e-mail domain prefilling from productive code")
            if let welcomeScreen = welcomeStepUI as? FUIWelcomeScreen {
                // Configuring WelcomeScreen to prefill the email domain
                welcomeScreen.emailTextField.text = ""
            }
        }

        return welcomeScreenStep
    }

    private func configuredUserConsentStep() -> UserConsentStep {
        let actionTitle = "Learn more about Data Privacy"
        let actionUrl = "https://www.sap.com/corporate/en/legal/privacy.html"
        let singlePageTitle = "Data Privacy"
        let singlePageText = "Detailed text about how data privacy pertains to this app and why it is important for the user to enable this functionality"

        var singlePageContent = UserConsentPageContent()
        singlePageContent.actionTitle = actionTitle
        singlePageContent.actionUrl = actionUrl
        singlePageContent.title = singlePageTitle
        singlePageContent.body = singlePageText
        let singlePageFormContent = UserConsentFormContent(version: "1.0", isRequired: true, pages: [singlePageContent])

        return UserConsentStep(userConsentFormsContent: [singlePageFormContent])
    }

    private func configuredStoreManagerStep() -> StoreManagerStep {
        let step = StoreManagerStep()
        step.defaultPasscodePolicy = nil

        return step
    }
}

// MARK: - SAPWKNavigationDelegate

// The WKWebView occasionally returns an NSURLErrorCancelled error if a redirect happens too fast.
// In case of OAuth with SAP's identity provider (IDP) we do not treat this as an error.
extension OnboardingFlowProvider: SAPWKNavigationDelegate {
    public func webView(_: WKWebView, handleFailed _: WKNavigation!, withError error: Error) -> Error? {
        if self.isCancelledError(error) {
            return nil
        }
        return error
    }

    public func webView(_: WKWebView, handleFailedProvisionalNavigation _: WKNavigation!, withError error: Error) -> Error? {
        if self.isCancelledError(error) {
            return nil
        }
        return error
    }

    private func isCancelledError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
