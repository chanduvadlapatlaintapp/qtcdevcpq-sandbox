/**
* @description Constant Class for Subscription object
* @author Suresh Somu
* @jira BIZ-66216
**/
public with sharing class SubscriptionConstants {
    
    // Subscription statuses
    public static final String SUBSCRIPTIONTYPE_ONETIME = 'One-time';
    public static final String SUBSCRIPTIONTYPE_EVERGREEN = 'Evergreen';
    
   // Option Types
   public final static String OPTION_TYPE_STATIC_BUNDLE = 'Static Bundle';
   public final static String OPTION_TYPE_STATIC_COMPONENT = 'Static Component';
    
   // ACV Types
   public static final String ACV_TYPE_SUBSCRIPTION_ADDON = 'Subscription Add-On';
}