/**
 * @author : Suresh Kumar
 * @description : Utility method for date conversion
 * @jira : BIZ-67254
 **/
public class DateUtils {
    
   /**
    * @description : Converts a date string in MM/DD/YYYY format to a Date object.
    * @param dateStr The date string (e.g., "4/17/2025")
    * @return Date object representing the input string
    **/
    public static Date stringToDate(String dateStr) {
        if (String.isBlank(dateStr)) {
            throw new IllegalArgumentException('Date string cannot be null or empty.');
        }

        List<String> parts = dateStr.split('/');
        if (parts.size() != 3) {
            throw new IllegalArgumentException('Date format must be MM/DD/YYYY.');
        }

        try {
            Integer month = Integer.valueOf(parts[0]);
            Integer day = Integer.valueOf(parts[1]);
            Integer year = Integer.valueOf(parts[2]);

            Date myDate = Date.newInstance(year, month, day);
            return myDate;
        } catch (Exception e) {
            throw new IllegalArgumentException('Invalid date string: ' + dateStr);
        }
    }
}