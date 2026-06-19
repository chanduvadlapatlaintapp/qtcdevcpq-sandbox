public class CompositeKeyMatrix {
        
        
        Map<String,List<String>> matrix;
        List<String> key1,key2,value;
        
        public CompositeKeyMatrix(String csvString) {
            matrix = new Map<String,List<String>>();
            matrix.put('key1',new List<String>());
            matrix.put('key2',new List<String>());
            matrix.put('value', new List<String>());
            Integer i = 0;
            List<String> lines = csvString.split('\\r\\n');
            for (String line: lines) {
                List<String> columns = line.split(',');
                i++;
                //DebugLogger.insertEntry('v' + String.valueOf(i),line + ' ' + String.valueOf(columns.size()));
                
                if (columns.size() != 3)
                    throw new CompositeKeyMatrixException('Matrix must have 3 columns');
                List<String> columnList = (List<String>)matrix.get('key1');
                columnList.add(columns[0]);
                columnList = (List<String>)matrix.get('key2');
                columnList.add(columns[1]);
                columnList = (List<String>)matrix.get('value');
                columnList.add(columns[2]);
                
               
            }
           
        }
        
        public String findValue(String key1Search, String key2Search) {
            for (Integer i = 0; i < matrix.get('key1').size(); i++) {
                if (
                    (matrix.get('key1').get(i) == key1Search) && 
                    ((matrix.get('key2').get(i) == key2Search) || (matrix.get('key2').get(i) == ''))
                   )
                    return matrix.get('value').get(i);
            }
            return '';
        }
     
    }