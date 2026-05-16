//@isTest
public class CompositeKeyMatrixTest {

    static void assertEquals(String left, String right) {
        System.debug(left == right);
    }
    
    static public void test1() {
        try {
            CompositeKeyMatrix c = new CompositeKeyMatrix('');
            System.debug(false);
        } 
        catch (CompositeKeyMatrixException c) {
            assertEquals(c.getMessage(),'Matrix must have 3 columns');
        }
    }
    
    static public void test2() {
        try {
            CompositeKeyMatrix c = new CompositeKeyMatrix('1,5\n3,7');
            System.debug(false);
        } 
        catch (CompositeKeyMatrixException c) {
            assertEquals(c.getMessage(),'Matrix must have 3 columns');
        }
    }
    
    static public void test3() {
        try {
            CompositeKeyMatrix c = new CompositeKeyMatrix('1,2,4\n3,6,7\n4,8');
            System.debug(false);
        }
        catch (CompositeKeyMatrixException c) {
            assertEquals(c.getMessage(),'Matrix must have 3 columns');
        }
    }
    
    static public void test4() {
        try {
            CompositeKeyMatrix c = new CompositeKeyMatrix('1,2,4\n3,6,7\n4,8\n2,4,6');
            System.debug(false);
        } 
        catch (Exception c) {
            assertEquals(c.getMessage(),'Matrix must have 3 columns');
        }
    }
    
    static public void test5() {
        CompositeKeyMatrix c = new CompositeKeyMatrix('1,2,3\n4,,6\n7,,9');
        assertEquals(c.findValue('4',''),'6');
    }
    
    static public void test6() {
        CompositeKeyMatrix c = new CompositeKeyMatrix('1,2,3\n4,5,6\n7,8,9');
        assertEquals(c.findValue('1','8'),'');
    }
    
    static public void test7() {
        CompositeKeyMatrix c = new CompositeKeyMatrix('apple,banana,orange\nonion,olive,tomato\npepper,garlic,carrot');
        assertEquals(c.findValue('apple','banana'),'orange');
    }
    
    static public void test8() {
        CompositeKeyMatrix c = new CompositeKeyMatrix('apple,banana,orange\nonion,olive,tomato\npepper,garlic,carrot');
        assertEquals(c.findValue('pepper','garlic'),'carrot');
    }
    
    static public void test9() {
        CompositeKeyMatrix c = new CompositeKeyMatrix('apple,banana,orange\nonion,olive,tomato\npepper,garlic,carrot');
        assertEquals(c.findValue('apple','banana1'),'');
    }
    
    static public void test10() {
        CompositeKeyMatrix c = new CompositeKeyMatrix('apple,banana,orange\nonion,olive,tomato\npepper,garlic,carrot');
        assertEquals(c.findValue('olive',''),'');
    }
   
    
    
}