//
//  Constants.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 1/29/25.
//

public struct Constants {

    public static let IDENTIFY_EVENT = "$identify"
    public static let GROUP_IDENTIFY_EVENT = "$groupidentify"


    public static let AMP_AMPLITUDE_PREFIX = "[Amplitude] "

    public static let AMP_SESSION_END_EVENT = "session_end"
    public static let AMP_SESSION_START_EVENT = "session_start"
    public static let AMP_APPLICATION_INSTALLED_EVENT = "\(AMP_AMPLITUDE_PREFIX)Application Installed"
    public static let AMP_APPLICATION_UPDATED_EVENT = "\(AMP_AMPLITUDE_PREFIX)Application Updated"
    public static let AMP_APPLICATION_OPENED_EVENT = "\(AMP_AMPLITUDE_PREFIX)Application Opened"
    public static let AMP_APPLICATION_BACKGROUNDED_EVENT = "\(AMP_AMPLITUDE_PREFIX)Application Backgrounded"
    public static let AMP_DEEP_LINK_OPENED_EVENT = "\(AMP_AMPLITUDE_PREFIX)Deep Link Opened"
    public static let AMP_SCREEN_VIEWED_EVENT = "\(AMP_AMPLITUDE_PREFIX)Screen Viewed"
    public static let AMP_ELEMENT_INTERACTED_EVENT = "\(AMP_AMPLITUDE_PREFIX)Element Interacted"

    public static let AMP_APP_VERSION_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)Version"
    public static let AMP_APP_BUILD_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)Build"
    public static let AMP_APP_PREVIOUS_VERSION_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)Previous Version"
    public static let AMP_APP_PREVIOUS_BUILD_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)Previous Build"
    public static let AMP_APP_FROM_BACKGROUND_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)From Background"
    public static let AMP_APP_LINK_URL_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)Link URL"
    public static let AMP_APP_LINK_REFERRER_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)Link Referrer"
    public static let AMP_APP_SCREEN_NAME_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)Screen Name"
    public static let AMP_APP_TARGET_AXLABEL_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)Target Accessibility Label"
    public static let AMP_APP_TARGET_AXIDENTIFIER_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)Target Accessibility Identifier"
    public static let AMP_APP_ACTION_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)Action"
    public static let AMP_APP_TARGET_VIEW_CLASS_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)Target View Class"
    public static let AMP_APP_TARGET_TEXT_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)Target Text"
    public static let AMP_APP_HIERARCHY_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)Hierarchy"
    public static let AMP_APP_ACTION_METHOD_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)Action Method"
    public static let AMP_APP_GESTURE_RECOGNIZER_PROPERTY = "\(AMP_AMPLITUDE_PREFIX)Gesture Recognizer"
}
