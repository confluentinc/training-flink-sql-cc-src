package com.confluent.training.udf;

import org.apache.flink.table.functions.ScalarFunction;

/**
 * Scalar UDF v2 - Multi-mode credit card masking.
 *
 * Supports two masking modes via method overloading:
 *   mask_card_number(card_number)            -> partial (last 4 visible): ****-****-****-6611
 *   mask_card_number(card_number, 'full')    -> fully masked:             ****-****-****-****
 *   mask_card_number(card_number, 'partial') -> last 4 visible:          ****-****-****-6611
 */
public class MaskCardNumber extends ScalarFunction {

    // v1 - backward compatible: shows last 4 digits
    public String eval(Long cardNumber) {
        return eval(cardNumber, "partial");
    }

    // v2 - configurable masking mode
    public String eval(Long cardNumber, String maskMode) {
        if (cardNumber == null) {
            return null;
        }

        String cardStr = String.valueOf(cardNumber);

        while (cardStr.length() < 16) {
            cardStr = "0" + cardStr;
        }

        if ("full".equalsIgnoreCase(maskMode)) {
            return "****-****-****-****";
        }

        // Default to partial (last 4 visible)
        String lastFour = cardStr.substring(cardStr.length() - 4);
        return "****-****-****-" + lastFour;
    }
}
