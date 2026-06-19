/**
 * @description Test class for LookupSearchResult data wrapper class
 * @author      Manisha
 * @date        2025-07-03
 */
@isTest
private class LookupSearchResultTest {

    @isTest
    static void testLookupSearchResultConstructorAndGetters() {
        // Arrange
        Id sampleId = '001000000000001AAA';
        String sObjectType = 'Account';
        String icon = 'standard:account';
        String title = 'Test Account';
        String subtitle = 'Billing Customer';

        // Act
        LookupSearchResult result = new LookupSearchResult(
            sampleId,
            sObjectType,
            icon,
            title,
            subtitle
        );

        // Assert
        System.assertEquals(sampleId, result.getId(), 'Id should match');
        System.assertEquals(sObjectType, result.getSObjectType(), 'sObjectType should match');
        System.assertEquals(icon, result.getIcon(), 'Icon should match');
        System.assertEquals(title, result.getTitle(), 'Title should match');
        System.assertEquals(subtitle, result.getSubtitle(), 'Subtitle should match');
    }
}