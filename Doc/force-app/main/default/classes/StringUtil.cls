/**
 * @author Sahal Mohamed
 * @date 02/12/2025
 * @description utility class for String operations
 **/
public inherited sharing class StringUtil {

    /**
     * @description This is used to generate a random unique string value
     *
     * @example 69e75c7e5583b3441a7987fed3070529
     * @return a unique string value
     */
    public static String generateUniqueString() {

        // get a random number and the current time in milliseconds
        String randomLong = String.valueOf(Crypto.getRandomLong());
        String timeMillis = String.valueOf(System.now().getTime());

        String stringToHash = (randomLong + timeMillis);

        // convert our string to a alpha numeric hash
        Blob hash = Crypto.generateDigest('MD5', Blob.valueOf(stringToHash));
        String hexDigest = EncodingUtil.convertToHex(hash);

        return hexDigest;
    }
}