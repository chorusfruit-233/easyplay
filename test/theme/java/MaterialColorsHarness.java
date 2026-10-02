import com.easyplay.easyplay.materialcolor.MaterialColors;
import java.util.*;
public final class MaterialColorsHarness {
  public static void main(String[] args) {
    List<Map<String, Long>> rows = MaterialColors.generate(
      Arrays.asList(0xff3f51b5L, 0xffff9ca8L, 0xff42a795L), args[0], args[1], Boolean.parseBoolean(args[2]));
    StringJoiner output = new StringJoiner(",", "[", "]");
    for (Map<String, Long> row : rows) {
      StringJoiner fields = new StringJoiner(",", "{", "}");
      new TreeMap<>(row).forEach((key, value) -> fields.add("\"" + key + "\":" + value));
      output.add(fields.toString());
    }
    System.out.println(output);
  }
}
