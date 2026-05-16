/**
 * @author Sahal Mohamed
 * @date 02/12/2025
 * @description a test data template factory to facilitate the testing of business logic in apex
 * @reference https://github.com/dhoechst/Salesforce-Test-Factory
 **/
@isTest
public without sharing class TestFactoryDefaults {

    /**********************************************************************************************
     *
     * Consts
     *
     ***********************************************************************************************/

    public final static String BAD_TEST_DATA =
        'Uh oh, it looks like we dont have the neccessary data to run this unit test.';

    /**********************************************************************************************
     *
     * Data Template Notes
     *
     ***********************************************************************************************/

    // To specify defaults for objects, use the naming convention [ObjectName]Defaults.
    // For custom objects, omit the __c from the Object Name

    /**********************************************************************************************
     *
     * User Templates
     *
     ***********************************************************************************************/

    /**
     * @description base user definition
     */
    public class UserDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {

            String lastName = 'Testly';
            String uniqueString = StringUtil.generateUniqueString();
            String adminRole = 'Unallocated';

            return new Map<Schema.SObjectField, Object> {
                User.FirstName => 'Test',
                User.LastName => lastName,
                User.Alias => uniqueString.substring(0, 8),
                User.Email => lastName + '.' + uniqueString + '@example.com',
                User.Username => lastName + '.' + uniqueString + '@example.com',
                User.TimeZoneSidKey => 'America/Chicago',
                User.LanguageLocaleKey => 'en_US',
                User.EmailEncodingKey => 'UTF-8',
                User.LocaleSidKey => 'en_US',
                User.UserRoleId => ROLES.get(adminRole).Id
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
         public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
                User.Username
            };
        }
    }

    /**
     * @description admin user definition
     */
    public class AdminUserDefaults implements TestFactory.FieldDefaults {

        private UserDefaults base = new UserDefaults();


        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {

            String adminProfileName = 'System Administrator';
            String adminRole = 'Unallocated';
            
            // use the UserDefaults as a base and extend / override for an admin user
            Map<Schema.SObjectField, Object> defaults = base.getFieldDefaults();

            defaults.putAll(
                new Map<Schema.SObjectField, Object> {
                    User.ProfileId => PROFILES.get(adminProfileName).Id,
                    User.UserRoleId => ROLES.get(adminRole).Id
                });
            
            return defaults;
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return base.getUniqueFields();
        }
    }

    /**
     * @description CRM Ops user definition
     */
    public class CRMOpsUserDefaults implements TestFactory.FieldDefaults {

        private UserDefaults base = new UserDefaults();


        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {

            String profileName = 'Contracts / CRM Ops';

            // use the UserDefaults as a base and extend / override for a sales user
            Map<Schema.SObjectField, Object> defaults = base.getFieldDefaults();

            defaults.putAll(
                new Map<Schema.SObjectField, Object> {
                    User.ProfileId => PROFILES.get(profileName).Id
                });

            return defaults;
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return base.getUniqueFields();
        }
    }



    /**********************************************************************************************
     *
     * Account Templates
     *
     ***********************************************************************************************/

    /**
     * @description base account definition
     */
    public class AccountDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {

            String recordTypeName = 'Accounts_Accounting';

            return new Map<Schema.SObjectField, Object> {
                Account.Name => generateUniqueString(),
                Account.RecordTypeId => RECORD_TYPES.get('Account').get(recordTypeName).Id,
                Account.NumberOfEmployees => 100
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> { };
        }
    }

    /**
     * @description legal account definition
     */
    public class LegalAccountDefaults implements TestFactory.FieldDefaults {

        private AccountDefaults base = new AccountDefaults();


        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {

            String recordTypeName = 'LegalAccounts';

            // use the AccountDefaults as a base and extend / override for a prospect account
            Map<Schema.SObjectField, Object> defaults = base.getFieldDefaults();

            defaults.putAll(
                new Map<Schema.SObjectField, Object> {
                    Account.RecordTypeId => RECORD_TYPES.get('Account').get(recordTypeName).Id,
                    Account.Type => 'Customer'
                });

            return defaults;
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return base.getUniqueFields();
        }
    }

    /**
     * @description partner account definition
     */
    public class PartnerAccountDefaults implements TestFactory.FieldDefaults {

        private AccountDefaults base = new AccountDefaults();


        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {

            String recordTypeName = 'Accounts_Partners';

            // use the AccountDefaults as a base and extend / override for a partner account
            Map<Schema.SObjectField, Object> defaults = base.getFieldDefaults();

            defaults.putAll(
                new Map<Schema.SObjectField, Object> {
                    Account.RecordTypeId => RECORD_TYPES.get('Account').get(recordTypeName).Id,
                    Account.Type => 'Partner'
                });

            return defaults;
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return base.getUniqueFields();
        }
    }

    /**********************************************************************************************
     *
     * Contact Templates
     *
     ***********************************************************************************************/

    /**
     * @description base contact definition
     */
    public class ContactDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                Contact.FirstName => 'First',
                Contact.LastName => 'Last',
                Contact.Title => 'CEO',
                Contact.Email => StringUtil.generateUniqueString() + '@example.com',
                Contact.MailingStreet => '123 Fake Street',
                Contact.MailingCity => 'San Mateo',
                Contact.MailingState => 'California',
                Contact.MailingPostalCode => '94403',
                Contact.MailingCountry => 'United States'
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
                Contact.LastName
            };
        }
    }

    /**********************************************************************************************
     *
     * Opportunity Templates
     *
     ***********************************************************************************************/

    /**
     * @description base opportunity definition
     */
    public class OpportunityDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {

            String recordTypeName = 'Sales_Legal';
            String firstStage = OPP_STAGES_OPEN[0];

            return new Map<Schema.SObjectField, Object> {
                Opportunity.Name => 'Test Opportunity',
                Opportunity.RecordTypeId => RECORD_TYPES.get('Opportunity').get(recordTypeName).Id,
                Opportunity.StageName => firstStage,
                Opportunity.CloseDate => System.today().addDays(91),
                Opportunity.Amount => 10000
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> { };
        }
    }

    /**
     * @description migration opportunity definition
     */
    public class MigrationOpportunityDefaults implements TestFactory.FieldDefaults {

        private OpportunityDefaults base = new OpportunityDefaults();


        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {

            // use the OpportunityDefaults as a base and extend / override for an open opp
            Map<Schema.SObjectField, Object> defaults = base.getFieldDefaults();

            String recordTypeName = OpportunityConstants.RT_MIGRATION_OPP;

            defaults.putAll(
                new Map<Schema.SObjectField, Object> {
                    Opportunity.RecordTypeId => RECORD_TYPES.get('Opportunity').get(recordTypeName).Id
                });

            return defaults;
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return base.getUniqueFields();
        }
    }

    /**
     * @description closed won opportunity definition
     */
    public class ClosedWonOpportunityDefaults implements TestFactory.FieldDefaults {

        private OpportunityDefaults base = new OpportunityDefaults();


        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {

            // use the OpportunityDefaults as a base and extend / override for a closed won opp
            Map<Schema.SObjectField, Object> defaults = base.getFieldDefaults();

            defaults.putAll(
                new Map<Schema.SObjectField, Object> {
                    Opportunity.StageName => OPP_STAGES_CLOSED_WON[0],
                    Opportunity.CloseDate => System.today()
                });

            return defaults;
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return base.getUniqueFields();
        }
    }

    /**********************************************************************************************
     *
     * Opportunity Contact Role Templates
     *
     ***********************************************************************************************/

    /**
     * @description base opp contact role definition
     */
    public class OpportunityContactRoleDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                OpportunityContactRole.IsPrimary => true,
                OpportunityContactRole.Role => 'Billing/Shipping'
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> { };
        }
    }

    /**********************************************************************************************
     *
     * Product Templates
     *
     ***********************************************************************************************/

    /**
     * @description base product record
     */
    public class ProductDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                Product2.Name => 'Product',
                Product2.IsActive => true,
                Product2.ProductCode => 'code',
                Product2.SBQQ__SubscriptionPricing__c => 'Fixed Price',
                Product2.SBQQ__SubscriptionType__c => 'Renewable'
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
                Product2.ProductCode
            };
        }
    }

    /**
     * @description Defaults for subscription products
     */
    public class SubscriptionProductDefaults implements TestFactory.FieldDefaults {

        private ProductDefaults base = new ProductDefaults();


        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {

            // use the ProductDefaults as a base and extend / override for a subscription prod
            Map<Schema.SObjectField, Object> defaults = base.getFieldDefaults();

            defaults.putAll(
                new Map<Schema.SObjectField, Object> {
                    Product2.SBQQ__BillingFrequency__c => 'Annual',
                    Product2.SBQQ__SubscriptionPricing__c => 'Fixed Price',
                    Product2.SBQQ__SubscriptionTerm__c => 12,
                    Product2.SBQQ__SubscriptionType__c => 'Renewable' 
                });

            return defaults;
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return base.getUniqueFields();
        }
    }

    /**
     * @description Defaults for cloud products
     */
    public class CloudProductDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                Product2.Name => 'Intapp Deal Cloud',
                Product2.IsActive => true,
                Product2.ProductCode => 'cloud'
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
                Product2.ProductCode
            };
        }
    }

    /**********************************************************************************************
     *
     * Pricebook Entry Templates
     *
     ***********************************************************************************************/

    /**
     * @description base pricebook entry record
     */
    public class PricebookEntryDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                PricebookEntry.Pricebook2Id => Test.getStandardPricebookId(),
                PricebookEntry.IsActive => true,
                PricebookEntry.UnitPrice => 1000.00
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> { };
        }
    }

    /**********************************************************************************************
     *
     * Opp line item Templates
     *
     ***********************************************************************************************/

    /**
     * @description base opp line item entry record
     */
    public class OpportunityLineItemDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                OpportunityLineItem.Quantity => 10,
                OpportunityLineItem.TotalPrice => 1000.00
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> { };
        }
    }

    /**********************************************************************************************
     *
     * CPQ Quote Templates
     *
     ***********************************************************************************************/

    /**
     * @description base SBQQ__Quote__c org definition
     */
    public class SBQQQuoteDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            
            String recordTypeName = 'Draft_Quote';
            
            return new Map<Schema.SObjectField, Object> {
                SBQQ__Quote__c.OP4I_Sales_Segment__c => '25-FS AM - NA IB Midmarket',
                SBQQ__Quote__c.Subsidiary__c => '01:200 Integration Appliance (US)',
                SBQQ__Quote__c.Quote_Stage__c => QuoteConstants.STATUS_CONFIGURE_PRODUCTS,
                SBQQ__Quote__c.SBQQ__StartDate__c => System.today().addDays(-180),
                SBQQ__Quote__c.SBQQ__EndDate__c => System.today().addDays(-180).addYears(1).addDays(-1),
                SBQQ__Quote__c.RecordTypeId => RECORD_TYPES.get('SBQQ__Quote__c').get(recordTypeName).Id
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
            };
        }
    }
    /**
     * @description A default for an approved primary quote
     */
    public class SBQQQuoteApprovedPrimaryDefaults implements TestFactory.FieldDefaults {

        private SBQQQuoteDefaults base = new SBQQQuoteDefaults();
        String recordTypeName = 'Approved_Quote';

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {

            // use the SBQQQuoteDefaults as a base and extend / override for an approved quote
            Map<Schema.SObjectField, Object> defaults = base.getFieldDefaults();

            defaults.putAll(
                new Map<Schema.SObjectField, Object> {
                    SBQQ__Quote__c.SBQQ__Primary__c => true,
                    SBQQ__Quote__c.RecordTypeId => RECORD_TYPES.get('SBQQ__Quote__c').get(recordTypeName).Id,
                    SBQQ__Quote__c.SBQQ__Status__c => 'Approved'
                });

            return defaults;
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return base.getUniqueFields();
        }
    }


    /**********************************************************************************************
     *
     * CPQ Quote Line Templates
     *
     ***********************************************************************************************/

    /**
     * @description base SBQQ__QuoteLine__c org definition
     */
    public class SBQQQuoteLineDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                SBQQ__QuoteLine__c.SBQQ__Quantity__c => 1,
                SBQQ__QuoteLine__c.SBQQ__Number__c => 1,
                SBQQ__QuoteLine__c.SBQQ__Discount__c => 10
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
                SBQQ__QuoteLine__c.SBQQ__Number__c
            };
        }
    }

    /**********************************************************************************************
     *
     * Contract Templates
     *
     ***********************************************************************************************/

    /**
     * @description base Contract definition
     */
    public class ContractDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                Contract.StartDate => Date.today().addDays(-180),
                Contract.ContractTerm => 12

            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
            };
        }
    }

    /**********************************************************************************************
     *
     * SBQQ__Subscription__c Templates
     *
     ***********************************************************************************************/

    /**
     * @description base SBQQ__Subscription__c definition
     */
    public class SBQQSubScriptionDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                SBQQ__Subscription__c.SBQQ__Quantity__c => 1,
                SBQQ__Subscription__c.SBQQ__ListPrice__c => 10000,
                SBQQ__Subscription__c.SBQQ__SubscriptionStartDate__c => System.today(),
                SBQQ__Subscription__c.SBQQ__SubscriptionEndDate__c => system.today().addMonths(12)
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
            };
        }
    }



    /**********************************************************************************************
     *
     * Order Templates
     *
     ***********************************************************************************************/

    /**
     * @description base Order org definition
     */
    public class OrderDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                Order.EffectiveDate => system.today(),
                Order.EndDate => system.today().addMonths(12),
                Order.Status => 'Draft'

            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
            };
        }
    }

    /**
     * @description Aproved order defaults
     */
    public class OrderApprovedDefaults implements TestFactory.FieldDefaults {

        private OrderDefaults base = new OrderDefaults();

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {

            // use the OrderDefaults as a base and extend / override for an approved order
            Map<Schema.SObjectField, Object> defaults = base.getFieldDefaults();

            defaults.putAll(
                new Map<Schema.SObjectField, Object> {
                    Order.Status => 'Approved'
                });

            return defaults;
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return base.getUniqueFields();
        }
    }


    /**********************************************************************************************
     *
     * Orderitem (order line) Templates
     *
     ***********************************************************************************************/

    /**
     * @description base Orderitem org definition
     */
    public class OrderItemDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                OrderItem.SBQQ__QuotedListPrice__c => 1000,
                OrderItem.UnitPrice => 1000,
                OrderItem.Quantity => 1

            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
            };
        }
    }

    /**********************************************************************************************
     *
     * Approval Rule (sbaa__ApprovalRule__c) Templates
     *
     ***********************************************************************************************/

    /**
     * @description base Approval Rule org definition
     */
    public class SbaaApprovalRuleDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                sbaa__ApprovalRule__c.Name => 'Test-Rule',
                sbaa__ApprovalRule__c.sbaa__TargetObject__c => 'SBQQ__Quote__c',
                sbaa__ApprovalRule__c.sbaa__Active__c => true
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
            };
        }
    }
    /**********************************************************************************************
     *
     * Approval (sbaa__Approval__c) Templates
     *
     ***********************************************************************************************/

    /**
     * @description base Approval org definition
     */
    public class SbaaApprovalDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                sbaa__Approval__c.sbaa__Status__c => 'Requested',
                sbaa__Approval__c.sbaa__ApprovalStep__c => 100,
                sbaa__Approval__c.sbaa__RecordField__c => 'Quote__c'


            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
            };
        }
    }

    /**********************************************************************************************
     *
     * CPQ Quote Term Templates
     *
     ***********************************************************************************************/

    /**
     * @description base SBQQ__QuoteTerm__c definition (global standard term)
     */
    public class SBQQQuoteTermDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                SBQQ__QuoteTerm__c.SBQQ__Body__c => 'Standard Quote Term Body',
                SBQQ__QuoteTerm__c.SBQQ__Active__c => true,
                SBQQ__QuoteTerm__c.SBQQ__PrintOrder__c => 1
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
                SBQQ__QuoteTerm__c.SBQQ__PrintOrder__c
            };
        }
    }

    /**********************************************************************************************
     *
     * Term Quote Templates
     *
     ***********************************************************************************************/

    /**
     * @description base Term_Quote__c definition
     */
    public class TermQuoteDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                Term_Quote__c.Body__c => 'Term Quote Body',
                Term_Quote__c.Print_Order__c => 1,
                Term_Quote__c.Validator_Modified__c => false,
                Term_Quote__c.Modified__c => false
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
                Term_Quote__c.Print_Order__c
            };
        }
    }

    /**********************************************************************************************
     *
     * Address Templates
     *
     ***********************************************************************************************/

    /**
     * @description base Address__c definition for approved billing/shipping addresses
     */
    public class AddressDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                Address__c.Address__City__s => 'Los Angeles',
                Address__c.Address__CountryCode__s => 'US',
                Address__c.Address__PostalCode__s => '90210',
                Address__c.Address__StateCode__s => 'CA',
                Address__c.Address__Street__s => 'Beverly Hills',
                Address__c.Status__c => 'Verification Approved',
                Address__c.Default_Billing_Address__c => true,
                Address__c.Default_Shipping_Address__c => true,
                Address__c.Department__c => 'Tax'
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
            };
        }
    }

    /**********************************************************************************************
     *
     * Automation Controls Templates
     *
     ***********************************************************************************************/

    /**
     * @description base Automation_Controls__c definition for test isolation
     */
    public class AutomationControlsDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                Automation_Controls__c.Active__c => true,
                Automation_Controls__c.Bypass_Flows__c => true,
                Automation_Controls__c.Bypass_Triggers__c => false,
                Automation_Controls__c.Quote_Bypass__c => true,
                Automation_Controls__c.Quoteline_Bypass__c => true
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
            };
        }
    }

    /**********************************************************************************************
     *
     * Lead Templates
     *
     ***********************************************************************************************/

    /**
     * @description base lead definition
     */
    public class LeadDefaults implements TestFactory.FieldDefaults {

        /**
         * @description A way to provide default values for specific definitions
         * 
         * @return a set of field schemas with default values
         */
        public Map<Schema.SObjectField, Object> getFieldDefaults() {
            return new Map<Schema.SObjectField, Object> {
                Lead.FirstName => 'Lead',
                Lead.LastName => 'Test',
                Lead.Company => 'Test Company'
            };
        }

        /**
         * @description set of unique fields for this class
         * 
         * @return a set of unique field schemas
         */
        public Set<Schema.SObjectField> getUniqueFields() {
            return new Set<Schema.SObjectField> {
                Lead.LastName,
                Lead.Company
            };
        }
    }

    /**********************************************************************************************
     *
     * Data Props / Utils
     *
     ***********************************************************************************************/

    /**
     * @description getter for profiles
     * keyed on profile name
     */
    @TestVisible
    private static final Map<String, Profile> PROFILES { //NOPMD
        get {
            if (PROFILES == null) {
                PROFILES = new Map<String, Profile> ();

                for (Profile prof :[SELECT Id, Name FROM Profile]) {
                    PROFILES.put(prof.Name, prof);
                }
            }
            return PROFILES;
        } set;
    }

    /**
     * @description getter for record types
     * outer map : key of object name
     * inner map : key of record type developer name
     */
    @TestVisible
    private static final Map<String, Map<String, RecordType>> RECORD_TYPES { //NOPMD
        get {
            if (RECORD_TYPES == null) {
                RECORD_TYPES = new Map<String, Map<String, RecordType>> ();

                for (RecordType recType :[SELECT Id, SobjectType, DeveloperName FROM RecordType]) {

                    if (!RECORD_TYPES.containsKey(recType.SobjectType)) {
                        RECORD_TYPES.put(recType.SobjectType, new Map<String, RecordType> ());
                    }
                    RECORD_TYPES.get(recType.SobjectType).put(recType.DeveloperName, recType);
                }
            }
            return RECORD_TYPES;
        } set;
    }

    /**
     * @description getter for closed won opp stages
     */
    @TestVisible
    private static final List<String> OPP_STAGES_CLOSED_WON { //NOPMD
        get {
            if (OPP_STAGES_CLOSED_WON == null) {
                OPP_STAGES_CLOSED_WON = new List<String> ();

                for (OpportunityStage stage : OPP_STAGES) {
                    if (stage.IsWon) {

                        OPP_STAGES_CLOSED_WON.add(stage.ApiName);
                    }
                }
            }
            return OPP_STAGES_CLOSED_WON;
        } set;
    }

    /**
     * @description getter for open opp stages
     */
    @TestVisible
    private static final List<String> OPP_STAGES_OPEN { //NOPMD
        get {
            if (OPP_STAGES_OPEN == null) {
                OPP_STAGES_OPEN = new List<String> ();

                for (OpportunityStage stage : OPP_STAGES) {
                    if (!stage.IsClosed) {

                        OPP_STAGES_OPEN.add(stage.ApiName);
                    }
                }
            }
            return OPP_STAGES_OPEN;
        } set;
    }

    /**
     * @description getter for all active opp stages
     * ordered by the stage sort order field
     */
    @TestVisible
    private static final List<OpportunityStage> OPP_STAGES { //NOPMD
        get {
            if (OPP_STAGES == null) {
                OPP_STAGES = [SELECT Id, ApiName,
                                IsActive,
                                IsClosed,
                                IsWon,
                                SortOrder
                            FROM OpportunityStage
                            WHERE IsActive = true
                            ORDER BY SortOrder
                            ];
            }
            return OPP_STAGES;
        } set;
    }

    /**
    * @description : This returns map of all active roles
    *
    * @return : { Map<String, UserRole> }
    */
    @TestVisible
    private static final Map<String, UserRole> ROLES {//NOPMD
        get {
            if(ROLES == null) {
                ROLES = new Map<String, UserRole>();
                for(UserRole role : [SELECT Id, Name
                                    FROM UserRole
                                    WHERE Name != 'Inactive']) {
                                        ROLES.put(role.Name, role);
                                    }
            }
            return ROLES;
        } set;
    }
    
    /**
    * @description : This returns map of non Admin Roles
    *
    * @return : { Map<String, UserRole> }
    */
    @TestVisible
    private static final Map<String, UserRole> NON_ADMIN_ROLES {//NOPMD
        get {
            if(NON_ADMIN_ROLES == null) {
                NON_ADMIN_ROLES = new Map<String, UserRole>();
                for(String role : ROLES.keySet()) {
                    if(role != 'Unallocated') {
                        NON_ADMIN_ROLES.put(role, ROLES.get(role));
                    }
                }
            }
            return ROLES;
        } set;
    }
    
    /**
     * @description This is used to generate a random unique string value
     *
     * @example 69e75c7e5583b3441a7987fed3070529
     * @return a unique string value
     */
    @TestVisible
    private static String generateUniqueString() {

        // get a random number and the current time in milliseconds
        String randomLong = String.valueOf(Crypto.getRandomLong());
        String timeMillis = String.valueOf(System.now().getTime());

        String stringToHash = (randomLong + timeMillis);

        // convert our string to a alpha numeric hash
        Blob hash = Crypto.generateDigest('MD5', Blob.valueOf(stringToHash));
        String hexDigest = EncodingUtil.convertToHex(hash);

        return hexDigest;
    }

    /**
     * @description This selects a random picklist value from the provided field
     *
     * @param field - a field to get a pickval from
     * @return a unique string value
     */
    @TestVisible
    private static String getRandomPickval(Schema.SObjectField field) {

        List<String> values = new List<String> ();

        Schema.DescribeFieldResult fieldResult = field.getDescribe();//NOPMD

        for (Schema.PicklistEntry pickListVal : fieldResult.getPicklistValues()) {
            values.add(pickListVal.getLabel());
        }

        return getRandomPickval(values);
    }

    /**
     * @description This selects and returns a random value in the list
     *
     * @param values - a list of string to get a value from
     * @return a unique string value
     */
    @TestVisible
    private static String getRandomPickval(List<String> values) {

        Integer index = getRandomInteger(values.size());
        return values[index];
    }

    /**
     * @description This selects a random number between 0 and the provided value
     *
     * @param num - an integer to select a value between
     * @return { Integer } a random integer value
     */
    @TestVisible
    private static Integer getRandomInteger(Integer num) {
        return(Math.random() * num).intValue();
    }
}