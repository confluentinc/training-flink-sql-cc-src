package com.confluent.training.udf;

import org.apache.flink.table.functions.ScalarFunction;

/**
 * Scalar UDF that masks a credit card number for PII compliance.
 *
 * Input:  6011601160116611 (BIGINT)
 * Output: ****-****-****-6611 (STRING)
 */
public class MaskCardNumber extends ScalarFunction {

    public String eval(Long cardNumber) {
        if (cardNumber == null) {
            return null;
        }

        String cardStr = String.valueOf(cardNumber);

        while (cardStr.length() < 16) {
            cardStr = "0" + cardStr;
        }

        String lastFour = cardStr.substring(cardStr.length() - 4);

        return "****-****-****-" + lastFour;
    }
}

