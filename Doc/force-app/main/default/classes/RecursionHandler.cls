public class RecursionHandler {
    public static Boolean isRecursive = false;
    public static Integer count = 0;
    public static Boolean checkRecursion(){
        Boolean returnFlag = isRecursive;
        count++;
        if(count == 3)
            isRecursive = true;
        return returnFlag;
    }
}